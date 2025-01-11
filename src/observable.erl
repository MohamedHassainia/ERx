%%%-------------------------------------------------------------------
-module(observable).

%% API
-export([create/1,
         from_list/1,
         from_value/1,
         zip2/2,
         zip/1,
         bind/2,
         pipe/2,
         subscribe/2]).

-export_type([t/2,
              state/0,
              item_producer/2]).

%%%===================================================================
%%% Includes, defines, types and records
%%%===================================================================
-include("observable_item.hrl").
-include("subscriber.hrl").

-type state() :: #{is_completed => boolean()}.
-type item_producer(A, E) :: fun((state()) -> {observable_item:t(A, E), state()}).

-record(observable, {
    state = #{is_completed => false} :: state(),
    item_producer                    :: item_producer(any(), any()),
    subscribers = []                 :: list(subscriber:t(any(), any()))
}).

-type t(A, ErrorInfo) :: #observable{
    state          :: state() | undefined,
    item_producer :: item_producer(A, ErrorInfo),
    subscribers    :: list(subscriber:t(A, ErrorInfo))
}.

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
subscribe(ObservableA, Subscribers) ->
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
-spec run(ObservableA) -> any()
    when ObservableA :: observable:t(A, ErrorInfo),
         A :: any(),
         ErrorInfo :: any().
%%--------------------------------------------------------------------
run(#observable{state = State} = ObservableA) ->
    run(ObservableA, State).

%%--------------------------------------------------------------------
-spec run(ObservableA, State) -> any()
    when ObservableA :: observable:t(A, ErrorInfo),
         State :: map(),
         A :: any(),
         ErrorInfo :: any().
%%--------------------------------------------------------------------
run(#observable{subscribers = Subscribers}, #{is_completed := true}) ->
    broadcast_item(?ON_COMPLETE, [], Subscribers);
run(#observable{item_producer = ItemProducer, subscribers = Subscribers} = ObservableA, State) ->
    {Item, NewState} = apply(ItemProducer, [State]),
    case Item of 
        ?NEXT(Value)      ->
            broadcast_item(?ON_NEXT, [Value], Subscribers),
            run(ObservableA, NewState);
        ?ERROR(ErrorInfo) ->
            broadcast_item(?ON_ERROR, [ErrorInfo], Subscribers);
        ?COMPLETE           -> 
            broadcast_item(?ON_COMPLETE, [], Subscribers);
        ?IGNORE             ->
            run(ObservableA, NewState)
    end.