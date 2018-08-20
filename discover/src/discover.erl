-module(discover).

-export([main/1]).

main([ConfFile]) ->
  application:ensure_all_started(discover),
  {ok, Config} = file:consult(ConfFile),
  OidGroups = proplists:get_value(oidgroups, Config, []),
  Devs = proplists:get_value(devs, Config, []),
  {ok, Data} = discover(Devs, OidGroups),
  Output = proplists:get_value(out, Config, standard_io),
  write_data(Data, Output),
  ok;

main(_) ->
  exit("invalid arguments").
  
%% Private

discover(Devs, OldGroups) ->
  Self = self(),
  Pids = [ erlang:spawn(fun () -> discover_one(Dev, OldGroups, Self) end) || Dev <- Devs ],
  Data = receive_data(Pids),
  {ok, Data}.

receive_data(Pids) ->
  receive_data(Pids, []).

receive_data([], Data) ->
  Data;
receive_data(Pids, Acc) ->
  receive
    {Pid, Result} when is_pid(Pid) ->
      case lists:member(Pid, Pids) of
        true ->
          case Result of
            {Dev, {ok, Data}} ->
              receive_data(Pids -- [Pid], [format(Dev, Data) | Acc]);
            {Dev, {error, Err}} ->
              receive_data(Pids -- [Pid], [format_err(Dev, Err) | Acc])
          end
      end
  end.

discover_one(Dev, OidGroups, Parent) ->
  case catch parse_dev_config(Dev, OidGroups) of
    {ok, AgentName, AgentOpts, Oids} ->
      ok = discover_snmp_manager:agent(AgentName, AgentOpts),
      Data = get_data(AgentName, Oids),
      Parent ! {self(), {Dev, {ok, Data}}};
    {error, Error} ->
      Parent ! {self(), {Dev, {error, Error}}}
  end.

parse_dev_config({RawIP, RawOids}, OidGroups) ->
  parse_dev_config({RawIP, RawOids, []}, OidGroups);

parse_dev_config({RawIP, RawOids, Config}, OidGroups) ->
  Oids = parse_oids(RawOids, OidGroups),
  IP = parse_ip(RawIP),
  AgentName = make_name(IP),
  AgentOpts = [ {address, IP}, {engine_id, "engineId"} | Config ],
  {ok, AgentName, AgentOpts, Oids}.

parse_oids(RawOids, OidGroups) ->
  parse_oids(RawOids, OidGroups, []).

parse_oids([], _, Oids) ->
  lists:reverse(Oids);

parse_oids([RawOid | RawOids], OidGroups, Acc) ->
  case RawOid of
    _ when is_atom(RawOid) ->
      Oids = proplists:get_value(RawOid, OidGroups, []),
      parse_oids(Oids ++ RawOids, OidGroups, Acc);
    _ when is_list(RawOid) ->
      NewAcc = case parse_oid(RawOid) of
        {ok, Oid} -> [ Oid | Acc ];
        _ -> Acc
      end,
      parse_oids(RawOids, OidGroups, NewAcc);
    _ ->
      parse_oids(RawOids, OidGroups, Acc)
  end.

parse_oid(RawOid) ->
  try
    {ok, lists:map(fun erlang:list_to_integer/1, string:tokens(RawOid, "."))}
  catch
    _:Err -> {error, Err}
  end.

parse_ip(RawIp) ->
  case inet:parse_ipv4strict_address(RawIp) of
    {ok, IP} -> IP;
    Other -> throw(Other)
  end.

make_name(IP) ->
  UID = erlang:monotonic_time(),
  lists:flatten(io_lib:format("~p#~p", [IP, UID])).

get_data(Agent, Oids) ->
  discover_snmp_manager:sync_get_next(Agent, Oids).

format(Dev, Data) ->
  RawIp = element(1, Dev),
  {RawIp, format_data(Data)}.

format_err(Dev, Err) ->
  RawIp = element(1, Dev),
  {RawIp, Err}.

format_data({error, Reason}) ->
  Reason;

format_data({ok, SnmpReply, _Remaining}) ->
  format_snmp_reply(SnmpReply).

format_snmp_reply({noError, _ErrIndex, VarBinds}) ->
  VarBinds;

format_snmp_reply({ErrStatus, _ErrIndex, VarBinds}) ->
  {ErrStatus, VarBinds}.

write_data(Data, IODev) ->
  io:format(IODev, "~p~n", [Data]).

