%%%-------------------------------------------------------------------
-module(observable).

%% API
-export([create/1,
         from_list/1,
         from_value/1,
         value/1,
         zip2/2,
         zip/1,
         merge/1,
         bind/2,
         pipe/2,
         subscribe/2,
         interval/1,
         timer/1]).

-export_type([t/2,
              state/0,
              item_producer/2]).

%%%===================================================================
%%% Includes, defines, types and records
%%%===================================================================
-include("observable_item.hrl").
-include("subscriber.hrl").
-include("observable.hrl").

-define(observable(State, StRef, ObDef),
    Ref = erlang:unique_integer(),
    ItemProducer = fun(State) -> ObDef end,
    #observable{item_producer = ItemProducer}
).

-define(observable(State, ObDef),
    ItemProducer = fun(State) -> ObDef end,
    #observable{item_producer = ItemProducer}
).

-define(stateless_observable(ObDef),
    ItemProducer = fun(State) -> {ObDef, State} end,
    #observable{item_producer = ItemProducer}
).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec create(ItemProducer) -> t(A, ErrorInfo) when
    ItemProducer :: item_producer(A, ErrorInfo),
    ErrorInfo     :: any(),
    A             :: any().
create(ItemProducer) ->
    #observable{item_producer = ItemProducer}.

%%--------------------------------------------------------------------
-spec bind(observable:t(A, ErrorInfo), operator:t(A, ErrorInfo, B)) 
         -> observable:t(B, ErrorInfo) 
            when A :: any(),
                 B :: any(),
                 ErrorInfo :: any().
%%--------------------------------------------------------------------
bind(ObservableA, Operator) ->
    apply(Operator, [ObservableA#observable.item_producer]).

%%--------------------------------------------------------------------
-spec subscribe(ObservableA, Subscribers) -> any() 
    when ObservableA :: observable:t(A, ErrorInfo),
         Subscribers  :: list(subscriber:t(A, ErrorInfo)),
         A :: any(),
         ErrorInfo :: any().
%%--------------------------------------------------------------------
subscribe(ObservableA, Subscriber) when is_record(Subscriber, subscriber) ->
    subscribe(ObservableA, [Subscriber]);
subscribe(ObservableA, Subscribers) when is_list(Subscribers) ->
    ObservableWithSubs = ObservableA#observable{subscribers = Subscribers},
    run(ObservableWithSubs).

%%--------------------------------------------------------------------
-spec from_list(List :: list(A)) -> observable:t(A, ErrorInfo)
    when A :: any(),
         ErrorInfo :: any().
%%--------------------------------------------------------------------
from_list([]) ->
    ?stateless_observable(?COMPLETE);
from_list([Head|Tail]) ->
    ?observable(State, Ref,
        begin
            case maps:get(Ref, State, undefined) of
                undefined ->
                    {?NEXT(Head), _State = maps:put(Ref, Tail, State)};
                [] -> 
                    {?COMPLETE, State};
                [Value|List] ->
                    {?NEXT(Value), _State = maps:put(Ref, List, State)}
             end
        end
    ).

%%--------------------------------------------------------------------
-spec from_value(Value :: A) -> observable:t(A, ErrorInfo)
     when A :: any(),
          ErrorInfo :: any().
%%--------------------------------------------------------------------
from_value(Value) ->
    ?stateless_observable(?NEXT(Value)).
    
-spec zip2(ObservableA, ObservableB) -> ObservableC
    when ObservableA :: observable:t(A, ErrorInfo),
         ObservableB :: observable:t(B, ErrorInfo),
         ObservableC :: observable:t({A, B}, ErrorInfo),
         A :: any(),
         B :: any(),
         ErrorInfo :: any().

%% TODO fix this observable
zip2(#observable{item_producer = ItemProducerA} = _ObservableA,
     #observable{item_producer = ItemProducerB} = _ObservableB) ->
    ?observable(State,
        begin
            {ItemA, NewStateA} = apply(ItemProducerA, [State]),
            {ItemB, NewStateB} = apply(ItemProducerB, [State]),
            NewState = maps:merge(NewStateA, NewStateB),
            {{ItemA, ItemB}, NewState}
        end      
    ).

-spec zip(Observables) -> Observable
    when Observable :: observable:t(list(), ErrorInfo),
         Observables :: list(observable:t(A, ErrorInfo)),
         A :: any(),
         ErrorInfo :: any().

zip(Observables) ->
    ?observable(State,
            apply_observables_and_zip_items(lists:reverse(Observables), [], State)
    ).

%%--------------------------------------------------------------------
-spec value(Value :: A) -> observable:t(A, ErrorInfo)
     when A :: any(),
          ErrorInfo :: any().
%%--------------------------------------------------------------------
value(Value) ->
    ?stateless_observable(?LAST(Value)).

%%--------------------------------------------------------------------    
-spec apply_observables_and_zip_items(Observables, Result, State) -> {observable_item:t(list(), ErrorInfo), state()} when
    Observables :: [observable:t(A, ErrorInfo)],
    Result      :: list(),
    State       :: state(),
    A           :: any(),
    ErrorInfo   :: any().
%%--------------------------------------------------------------------
apply_observables_and_zip_items([], Result, State) ->
    {?NEXT(Result), State};
apply_observables_and_zip_items([Observable | Observables], Result, State) ->
    #observable{item_producer = ItemProducer} = Observable,
    
     case apply(ItemProducer, [State]) of
        {?IGNORE, NewState} -> 
            MergedNewState = maps:merge(State, NewState),
            apply_observables_and_zip_items(Observables, Result, MergedNewState);
        {?NEXT(Item), NewState} ->
            MergedNewState = maps:merge(State, NewState),
            apply_observables_and_zip_items(Observables, [Item|Result], MergedNewState);
        {?ERROR(ErrorInfo), NewState} ->
            {?ERROR(ErrorInfo), maps:merge(State, NewState)};
        {?COMPLETE, NewState} ->
            {?COMPLETE, maps:merge(State, NewState)}
    end.

%%--------------------------------------------------------------------
-spec merge(Observables) -> observable:t(any(), ErrorInfo) when
    Observables :: list(observable:t(A, ErrorInfo)),
    A :: any(),
    ErrorInfo :: any().
%%--------------------------------------------------------------------
merge([]) ->
    ?stateless_observable(?COMPLETE);
merge(Observables) when is_list(Observables) ->
    ?observable(State, Ref,
        begin
            Obs = maps:get(Ref, State, Observables),
            merge_observables(Ref, Obs, State)
        end
    ).

%%--------------------------------------------------------------------
-spec merge_observables(Ref, Observables, State) -> {Item, State} when
    Ref :: integer(),
    Observables :: list(observable:t(A, ErrorInfo)),
    State :: state(),
    Item :: observable_item:t(any(), ErrorInfo),
    A :: any(),
    ErrorInfo :: any().
%%--------------------------------------------------------------------
merge_observables(_Ref, [], State) ->
    {?COMPLETE, State};
merge_observables(Ref, [Observable | Obs], State) ->
    {Item, NewState} = apply_observable(Observable, State),
    case {Item, Obs} of
        {?ERROR(_ErrorInfo), _} ->
            {Item, maps:put(Ref, Obs, NewState)};
        {?COMPLETE, []} ->
            {?COMPLETE, NewState};
        {?COMPLETE, _} ->
            merge_observables(Ref, Obs, State);
        {Item, _} ->
            {Item, maps:put(Ref, Obs ++ [Observable], NewState)}
    end.

%%--------------------------------------------------------------------
-spec pipe(Observable, Operators) -> observable:t(A, ErrorInfo) when
    A :: any(),
    ErrorInfo :: any(),
    Observable :: observable:t(any(), ErrorInfo),
    Operators  :: list(operator:t(any(), ErrorInfo)).
%%--------------------------------------------------------------------
pipe(Observable, Operators) ->
    lists:foldl(fun(OperatorA, ObservableA) -> 
                    bind(ObservableA, OperatorA)
                end, Observable, Operators).


%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
-spec apply_observable(observable:t(A, ErrorInfo), State) -> {Item, State} when
    Item :: observable_item:t(A, ErrorInfo),
    State :: state(),
    A :: any(),
    ErrorInfo :: any().
%%--------------------------------------------------------------------
apply_observable(#observable{item_producer = ItemProducer}, State) ->
    apply(ItemProducer, [State]).

%%--------------------------------------------------------------------
-spec broadcast_item(CallbackFunName, Args, Subscribers) -> list() when
    CallbackFunName :: on_next | on_complete | on_error,
    Args :: list(),
    Subscribers :: list(subscriber:t(A, ErrorInfo)),
    A :: any(),
    ErrorInfo :: any().
%%--------------------------------------------------------------------
broadcast_item(CallbackFunName, Args, Subscribers) ->
    SubsCallbackFuns = 
        [subscriber:get_callback_function(CallbackFunName, Subscriber) || Subscriber <- Subscribers],

    [apply(CallbackFun, Args) ||  CallbackFun <- SubsCallbackFuns, CallbackFun /= undefined].

%%--------------------------------------------------------------------
-spec run(ObservableA) -> list()
    when ObservableA :: observable:t(A, ErrorInfo),
         A :: any(),
         ErrorInfo :: any().
%%--------------------------------------------------------------------
run(#observable{state = State} = ObservableA) ->
    run(ObservableA, State).

%%--------------------------------------------------------------------
-spec run(ObservableA, State) -> list()
    when ObservableA :: observable:t(A, ErrorInfo),
         State :: map(),
         A :: any(),
         ErrorInfo :: any().
%%--------------------------------------------------------------------
% run(#observable{subscribers = Subscribers}, #{is_completed := true}) ->
%     broadcast_item(?ON_COMPLETE, [], Subscribers),
%     [?COMPLETE];
run(#observable{item_producer = ItemProducer, subscribers = Subscribers} = ObservableA, State) ->
    {Item, NewState} = apply(ItemProducer, [State]),
    case Item of
        ?NEXT(Value)      ->
            broadcast_item(?ON_NEXT, [Value], Subscribers),
            [Item | run(ObservableA, NewState)];
        ?LAST(Value)      ->
            broadcast_item(?ON_NEXT, [Value], Subscribers),
            broadcast_item(?ON_COMPLETE, [], Subscribers),
            [?NEXT(Value) | [?COMPLETE]];
        ?ERROR(ErrorInfo) ->
            broadcast_item(?ON_ERROR, [ErrorInfo], Subscribers),
            [?ERROR(ErrorInfo)];
        ?COMPLETE           -> 
            broadcast_item(?ON_COMPLETE, [], Subscribers),
            [?COMPLETE];
        ?HALT              -> 
            [?HALT | run(ObservableA, NewState)];
        ?IGNORE             ->
            [?IGNORE | run(ObservableA, NewState)]
    end.
    
%%--------------------------------------------------------------------
%% @doc Creates an observable that emits incremental integers every interval
%% @end
%%--------------------------------------------------------------------
-spec interval(Interval :: pos_integer()) -> t(non_neg_integer(), any()).
interval(Interval) ->
    Producer = fun(State) ->
        Counter = maps:get(counter, State, 0),
        {?NEXT(Counter), State#{counter => Counter + 1}}
    end,
    create_server_observable(Producer, Interval).

%%--------------------------------------------------------------------
%% @doc Creates an observable that emits a single value after delay
%% @end
%%--------------------------------------------------------------------
-spec timer(Delay :: pos_integer()) -> t(integer(), any()).
timer(Delay) ->
    Producer = fun(_State) -> {?LAST(0), #{}} end,
    create_server_observable(Producer, Delay).

%%--------------------------------------------------------------------
%% Internal functions for server-based observables
%%--------------------------------------------------------------------
create_server_observable(Producer, Interval) ->
    create(fun(State) ->
        case maps:get(server_pid, State, undefined) of
            undefined ->
                {ok, Pid} = observable_server:start_link(Producer, Interval),
                {?IGNORE, State#{server_pid => Pid}};
            _Pid ->
                {?IGNORE, State}
        end
    end).