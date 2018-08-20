%%%-------------------------------------------------------------------
%% @doc discover top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(discover_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

%%====================================================================
%% API functions
%%====================================================================

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%====================================================================
%% Supervisor callbacks
%%====================================================================

%% Child :: {Id,StartFunc,Restart,Shutdown,Type,Modules}
init([]) ->
    ChildSpecs = [{discover_snmp_manager,
                   {discover_snmp_manager, start_link, []},
                   permanent,
                   5000,
                   worker,
                   [discover_snmp_manager]}],
    {ok, { {one_for_all, 0, 1}, ChildSpecs} }.

%%====================================================================
%% Internal functions
%%====================================================================
