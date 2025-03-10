%%%-------------------------------------------------------------------
-module(operator).

%% API
-export([map/1,
         any/1,
         all/1,
         drop/1,
         drop_while/1,
         take/1,
         take_while/1,
         filter/1,
         reduce/2,
         sum/0,
         product/0,
         reduce/1,
         distinct/0,
         distinct_until_changed/0]).

%%%===================================================================
%%% Includes, defines, types and records
%%%===================================================================
-include("observable_item.hrl").
-include("observable.hrl").

-type t(A, ErrorInfo, B) :: fun((observable:item_producer(A, ErrorInfo)) -> observable:t(B, ErrorInfo)).

-define(operator(ItemProducer, State, OpDef),
        Ref = erlang:unique_integer(),
        fun(ItemProducer) ->
            observable:create(
                fun(State) ->
                    OpDef
                end
            )
        end
).

-define(stateful_operator(ItemProducer, Ref, State, DefaultState, StateHandling1, StateHandling2),
        Ref = erlang:unique_integer(),
        fun(ItemProducer) ->
            observable:create(
                fun(State) ->
                    case maps:get(Ref, State, DefaultState) of
                      StateHandling1;
                      StateHandling2
                    end
                end
            )
        end
).

-define(state_handling(State, StateHandling), State -> StateHandling).

-define(default_operator(Handler),
        Ref = erlang:unique_integer(),
        fun(ItemProducer) ->
            observable:create(
                fun(BaseState) ->
                    {ProducedItem, ProducedState} = apply(ItemProducer, [BaseState]),
                    Handler(ProducedItem, BaseState, ProducedState, Ref)
                end
            )
        end
).

-define(statefull_operator(Handler),
        Ref = erlang:unique_integer(),
        fun(ItemProducer) ->
            observable:create(
                fun(BaseState) ->
                    {ProducedItem, ProducedState} = apply(ItemProducer, [BaseState]),
                    OperatorState = maps:get(Ref, ProducedState, undefined),
                    Handler(ProducedItem, BaseState, ProducedState, Ref, OperatorState)
                end
            )
        end
).

-define(stateless_operator(Handler),
        fun(ItemProducer) ->
            observable:create(
                fun(BaseState) ->
                    {ProducedItem, ProducedState} = apply(ItemProducer, [BaseState]),
                    {Handler(ProducedItem), ProducedState}
                end
            )
        end
).


%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec map(MapFun :: fun((A) -> B)) -> t(A, ErrorInfo :: any(), B) when
    A :: any(),
    B :: any().
%%--------------------------------------------------------------------
map(MapFun) ->
    ?stateless_operator(
        fun(?NEXT(Value)) ->
            ?NEXT(MapFun(Value));
           (?LAST(Value)) ->
            ?LAST(MapFun(Value));
           (Item) -> Item
        end
    ).

%%--------------------------------------------------------------------
-spec filter(Pred) -> operator:t(A, ErrorInfo, A)
    when Pred :: fun((A) -> boolean()),
         A    :: any(),
         ErrorInfo :: any().
%%--------------------------------------------------------------------
filter(Pred) ->
    ?stateless_operator(
        fun(?NEXT(Value)) ->
              case Pred(Value) of
                true -> ?NEXT(Value);
                false -> ?IGNORE
              end;
           (?LAST(Value)) ->
              case Pred(Value) of
                true -> ?LAST(Value);
                false -> ?COMPLETE
              end;
           (Item) -> Item   
        end
    ).

%%--------------------------------------------------------------------
-spec take(N :: integer()) -> operator:t(A, ErrorInfo, A)
    when A :: any(),
         ErrorInfo :: any().
%%--------------------------------------------------------------------
take(N) when N >= 0 ->
    ?default_operator(
        fun(?NEXT(Value), State, NewState, StRef) ->
            NItemLeftToTake = maps:get(StRef, State, N),
            case NItemLeftToTake of
                0 -> {?COMPLETE, NewState};
                1 -> {?LAST(Value), maps:put(StRef, 0, NewState)};
                _ -> {?NEXT(Value), maps:put(StRef, NItemLeftToTake - 1, NewState)}
            end;

        (?LAST(Value), State, NewState, StRef) ->
            NItemLeftToTake = maps:get(StRef, State, N),
            case NItemLeftToTake > 0 of
                true -> {?LAST(Value), NewState};
                false -> {?COMPLETE, NewState}
            end;

        (Item, _State, NewState, _StRef) ->
            {Item, NewState}
        end
    ).

%%--------------------------------------------------------------------
-spec take_while(Pred) -> operator:t(A, ErrorInfo, A) when
    Pred :: fun((A) -> boolean()),
    A :: any(),
    ErrorInfo :: any().
%%--------------------------------------------------------------------
take_while(Pred) ->
    ?default_operator(
        fun(?NEXT(Value), _State, NewState, _StRef) ->
            case Pred(Value) of
                true  -> {?NEXT(Value), NewState};
                false -> {?COMPLETE, NewState}
            end;

        (?LAST(Value), _State, NewState, _StRef) ->
            case Pred(Value) of
                true  -> {?LAST(Value), NewState};
                false -> {?COMPLETE, NewState}
            end;

        (Item, _State, NewState, _StRef) ->
            {Item, NewState}
        end
    ).

%%--------------------------------------------------------------------
-spec any(Pred :: fun((A) -> boolean())) -> operator:t(A, ErrorInfo, boolean()) when
    A :: any(),
    ErrorInfo :: any().
%%--------------------------------------------------------------------
any(Pred) ->
    ?default_operator(
        fun(?NEXT(Value), _State, NewState, _StRef) ->
             case Pred(Value) of
                true  -> {?LAST(true), NewState};
                false -> {?IGNORE, NewState}
             end;

        (?LAST(Value), _State, NewState, _StRef) ->
            case Pred(Value) of
                true  -> {?LAST(true), NewState};
                false -> {?COMPLETE, NewState}
            end;

        (?COMPLETE, _State, NewState, _StRef) ->
            {?LAST(false), NewState};
            
        (Item, _State, NewState, _StRef) ->
            {Item, NewState}
       end
    ).

%%--------------------------------------------------------------------
-spec all(Pred) -> observable_item:t(A, ErrorInfo)
    when
        Pred :: fun((A) -> boolean()),
        A    :: any(),
        ErrorInfo :: any().
%%--------------------------------------------------------------------
all(Pred) ->
    ?default_operator(
        fun(?NEXT(Value), _State, NewState, _StRef) ->
              case Pred(Value) of
                true  -> {?IGNORE, NewState};
                false -> {?LAST(false), NewState}
              end;

        (?LAST(Value), _State, NewState, _StRef) ->
            case Pred(Value) of
                true  -> {?IGNORE, NewState};
                false -> {?LAST(false), NewState}
            end;

        (?COMPLETE, _State, NewState, _StRef) ->
            {?LAST(true), NewState};

        (Item, _State, NewState, _StRef) ->
            {Item, NewState}
        end
    ).

%%--------------------------------------------------------------------
-spec drop(N :: non_neg_integer()) -> operator:t(any(), any(), any()).
%%--------------------------------------------------------------------
drop(N) ->
    ?default_operator(
        fun(Item, State, NewState, StRef) ->
            NItemLeftToDrop = maps:get(StRef, State, N),
            case Item of
                ?NEXT(_Value) when NItemLeftToDrop > 0 ->
                    {?IGNORE, maps:put(StRef, NItemLeftToDrop - 1, NewState)};
                ?LAST(_Value) when NItemLeftToDrop > 0 ->
                    {?COMPLETE, NewState};
                Item ->
                    {Item, maps:put(StRef, NItemLeftToDrop, NewState)}
            end
        end
    ).

%%--------------------------------------------------------------------
-spec drop_while(Pred) -> operator:t(A, ErrorInfo, A)
    when
        Pred :: fun((A) -> boolean()),
        A    :: any(),
        ErrorInfo :: any().
%%--------------------------------------------------------------------
drop_while(Pred) ->
    %% double check Haskell's take_while
    ?operator(ItemProducer, State,
        begin
            MustDrop = maps:get(Ref, State, true),
            {Item, NewState} = apply(ItemProducer, [State]),
            case MustDrop of
                false ->
                    {Item, NewState};
                true ->
                    drop_item(Item, Pred, NewState, Ref)
            end
        end).

%%--------------------------------------------------------------------
-spec reduce(Fun, InitialValue) -> operator:t(A, ErrorInfo, Acc) when
    Fun :: fun((A, Acc) -> Acc),
    A :: any(),
    Acc :: any(),
    InitialValue :: Acc,
    ErrorInfo :: any().
%%--------------------------------------------------------------------
reduce(Fun, InitialValue) ->
    ?default_operator(
        fun(?NEXT(Value), State, NewState, StRef) ->
            CurrentAcc = maps:get(StRef, State, InitialValue),
            NewAcc = Fun(Value, CurrentAcc),
            {?IGNORE, maps:put(StRef, NewAcc, NewState)};

        (?LAST(Value), State, NewState, StRef) ->
            CurrentAcc = maps:get(StRef, State, InitialValue),
            FinalAcc = Fun(Value, CurrentAcc),
            {?LAST(FinalAcc), NewState};

        (?COMPLETE, State, NewState, StRef) ->
            FinalAcc = maps:get(StRef, State, InitialValue),
            {?LAST(FinalAcc), NewState};

        (Item, _State, NewState, _StRef) ->
            {Item, NewState}
        end
    ).

%%--------------------------------------------------------------------
-spec reduce(Fun :: fun((A, A) -> A)) -> operator:t(A, ErrorInfo, A) when
    A :: any(),
    ErrorInfo :: any().
%%--------------------------------------------------------------------
reduce(Fun) ->
    ?default_operator(
        fun(?NEXT(Value), State, NewState, StRef) ->
            case maps:get(StRef, State, undefined) of
                undefined ->
                    % First value becomes initial accumulator
                    {?IGNORE, maps:put(StRef, Value, NewState)};
                Acc ->
                    % Subsequent values are reduced using the function
                    NewAcc = Fun(Value, Acc),
                    {?IGNORE, maps:put(StRef, NewAcc, NewState)}
            end;

        (?LAST(Value), State, NewState, StRef) ->
            case maps:get(StRef, State, undefined) of
                undefined ->
                    % Complete without any values
                    {?ERROR(no_values), NewState};
                Acc ->
                    % Emit final accumulated value
                    FinalAcc = Fun(Value, Acc),
                    {?LAST(FinalAcc), NewState}
            end;

        (?COMPLETE, State, NewState, StRef) ->
            case maps:get(StRef, State, undefined) of
                undefined ->
                    % Complete without any values
                    {?ERROR(no_values), NewState};
                FinalAcc ->
                    % Emit final accumulated value
                    {?LAST(FinalAcc), NewState}
            end;

        (Item, _State, NewState, _StRef) ->
            {Item, NewState}
        end
    ).

%%--------------------------------------------------------------------
-spec sum() -> operator:t(number(), ErrorInfo, number()) when
    ErrorInfo :: any().
%%--------------------------------------------------------------------
sum() ->
    reduce(fun(X, Acc) -> X + Acc end, 0).

%%--------------------------------------------------------------------
-spec product() -> operator:t(number(), ErrorInfo, number()) when
    ErrorInfo :: any().
%%--------------------------------------------------------------------
product() ->
    reduce(fun(X, Acc) -> X * Acc end, 1).

%%--------------------------------------------------------------------
-spec distinct() -> operator:t(A, ErrorInfo, A) when
    A :: any(),
    ErrorInfo :: any().
%%--------------------------------------------------------------------
distinct() ->
    ?default_operator(
        fun(?NEXT(Value), State, NewState, StRef) ->
            SeenValues = maps:get(StRef, State, sets:new()),
            case sets:is_element(Value, SeenValues) of 
                true -> {?IGNORE, NewState};
                false -> 
                    NewSeenValues = sets:add_element(Value, SeenValues),
                    {?NEXT(Value), maps:put(StRef, NewSeenValues, NewState)}
            end;
        (?LAST(Value), State, NewState, StRef) ->
            SeenValues = maps:get(StRef, State, sets:new()),
            case sets:is_element(Value, SeenValues) of 
                true -> {?COMPLETE, NewState};
                false -> 
                    NewSeenValues = sets:add_element(Value, SeenValues),
                    {?LAST(Value), maps:put(StRef, NewSeenValues, NewState)}
            end;
        (Item, _State, NewState, _StRef) ->
            {Item, NewState}
        end
    ).

%%--------------------------------------------------------------------
-spec distinct_until_changed() -> operator:t(A, ErrorInfo, A) when
    A :: any(),
    ErrorInfo :: any().
%%--------------------------------------------------------------------
distinct_until_changed() ->
    UniqueValue = {unique_int, erlang:unique_integer()},

    ?default_operator(
        fun(?NEXT(Value), State, NewState, StRef) ->
            PrevValue = maps:get(StRef, State, UniqueValue),
            case PrevValue of
                UniqueValue -> {?NEXT(Value), maps:put(StRef, Value, NewState)};
                Value -> {?IGNORE, NewState};
                _ -> {?NEXT(Value), maps:put(StRef, Value, NewState)}
            end;
        (?LAST(Value), State, NewState, StRef) ->
            PrevValue = maps:get(StRef, State, UniqueValue),
            case PrevValue of
                UniqueValue -> {?LAST(Value), maps:put(StRef, Value, NewState)};
                Value -> {?COMPLETE, NewState};
                _ -> {?LAST(Value), maps:put(StRef, Value, NewState)}
            end;
        (Item, _State, NewState, _StRef) ->
            {Item, NewState}
        end
    ).



%%%===================================================================
%%% Internal functions
%%%===================================================================


%%--------------------------------------------------------------------
-spec drop_item(Item, MustDropPred, State, MustDropRef) -> {observable_item:t(A, ErrorInfo), map()} when
    Item :: observable_item:t(A, ErrorInfo),
    
    A :: any(),
    ErrorInfo :: any(),
    MustDropPred :: fun((A) -> boolean()),
    State :: map(),
    MustDropRef :: any().
%%--------------------------------------------------------------------
drop_item(?NEXT(Value) = Item, MustDropPred, State, MustDropRef) ->
    case MustDropPred(Value) of
        true ->
            {?IGNORE, maps:put(MustDropRef,  true, State)};
        false ->
            {Item, maps:put(MustDropRef, false, State)}
    end;
drop_item(?LAST(Value), MustDropPred, State, MustDropRef) ->
    case MustDropPred(Value) of
        true ->
            {?COMPLETE, maps:put(MustDropRef, true, State)};
        false ->
            {?LAST(Value), maps:put(MustDropRef, false, State)}
    end;
drop_item(Item, _MustDropPred, State, MustDropRef) ->
    {Item, maps:put(MustDropRef, true, State)}.
