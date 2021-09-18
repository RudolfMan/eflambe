%%%-------------------------------------------------------------------
%%% @doc
%%% E flambe server stores state for all traces that have been started. When
%%% No traces remain the server will shut down automatically.
%%% @end
%%%-------------------------------------------------------------------
-module(eflambe_server).

-behaviour(gen_server).

%% API
-export([start_link/0, start_trace/3, stop_trace/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2]).

-include_lib("kernel/include/logger.hrl").

-define(SERVER, ?MODULE).


-record(state, {traces = [] :: [trace()]}).

-record(trace, {
          id :: any(),
          max_calls :: integer(),
          calls :: integer(),
          running = false :: boolean(),
          options = [] :: list()
         }).

-type state() :: #state{}.
-type trace() :: #trace{}.
-type from() :: {pid(), Tag :: term()}.

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec start_link() -> {ok, pid()} | ignore | {error, Error :: any()}.

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

start_trace(Id, MaxCalls, Options) ->
    gen_server:call(?SERVER, {start_trace, Id, MaxCalls, Options}).

stop_trace(Id) ->
    gen_server:call(?SERVER, {stop_trace, Id}).


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

-spec init(Args :: list()) -> {ok, state()}.

init([]) ->
    {ok, #state{}}.

-spec handle_call(Request :: any(), from(), state()) ->
                                  {reply, Reply :: any(), state()} |
                                  {reply, Reply :: any(), state(), timeout()} |
                                  {noreply, state()} |
                                  {noreply, state(), timeout()} |
                                  {stop, Reason :: any(), Reply :: any(), state()} |
                                  {stop, Reason :: any(), state()}.

handle_call({start_trace, Id, MaxCalls, Options}, _From, State) ->
    case get_trace_by_id(State, Id) of
        undefined ->
            % Create new trace
            NewState = put_trace(State, #trace{id = Id, max_calls = MaxCalls, calls = 0, options = Options, running = true}),
            {reply, {ok, Id}, NewState};
        #trace{max_calls = MaxCalls, calls = Calls, options = Options, running = false} = Trace ->
            % Increment existing trace
            NewCalls = Calls + 1,
            case NewCalls =:= MaxCalls of
                true ->
                    % End trace
                    NewState = update_trace(State, Id, Trace#trace{calls = NewCalls, running = true}),
                    {reply, {end_trace, Id, NewCalls, Options}, NewState};
                false ->
                    % Update number of calls
                    NewState = update_trace(State, Id, Trace#trace{calls = NewCalls, running = true}),
                    {reply, {ok, Id}, NewState}
            end;
        #trace{max_calls = MaxCalls, options = Options, running = true} ->
            {reply, {ok, Id}, State}
    end;

handle_call({stop_trace, Id}, _From, State) ->
    case get_trace_by_id(State, Id) of
        undefined ->
            {reply, {error, unknown_trace}, State};
        #trace{calls = Calls, options = Options, running = true} = Trace ->
            NewState = update_trace(State, Id, Trace#trace{running = false}),
            Reply = {ok, Id, Calls, Options},
            {reply, Reply, NewState};
        #trace{calls = Calls, options = Options, running = false} ->
            {reply, {ok, Id, Calls, Options}, State}
    end;

handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

-spec handle_cast(any(), state()) -> {noreply, state()} |
                                 {noreply, state(), timeout()} |
                                 {stop, Reason :: any(), state()}.

handle_cast(_Msg, State) ->
    {noreply, State}.

-spec handle_info(Info :: any(), state()) -> {noreply, state()} |
                                  {noreply, state(), timeout()} |
                                  {stop, Reason :: any(), state()}.

handle_info(Info, State) ->
    logger:error("Received unexpected info message: ~w",[Info]),
    {noreply, State}.

-spec terminate(Reason :: any(), state()) -> any().

terminate(_Reason, _State) ->
    ok.

%%%===================================================================
%%% Internal functions
%%%===================================================================

get_trace_by_id(#state{traces = Traces}, Id) ->
    case lists:filter(lookup_fun(Id), Traces) of
        [] -> undefined;
        [Trace] -> Trace
    end.

put_trace(#state{traces = ExistingTraces} = State, NewTrace) ->
    State#state{traces = [NewTrace|ExistingTraces]}.

update_trace(#state{traces = ExistingTraces} = State, Id, UpdatedTrace) ->
    {[_Trace], Rest} = lists:partition(lookup_fun(Id), ExistingTraces),
    State#state{traces = [UpdatedTrace|Rest]}.

lookup_fun(Id) ->
    fun
        (#trace{id = TraceId}) when TraceId =:= Id -> true;
        (_) -> false
    end.
