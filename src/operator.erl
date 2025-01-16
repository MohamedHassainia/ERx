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
         distinct_until_changed/0,
         flat_map/1]).  % Add flat_map to exports

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
        fun(Item) ->
            observable_item:liftM(MapFun, Item)
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
           (Item) -> Item   
        end
    ).

%%--------------------------------------------------------------------
-spec take(N :: integer()) -> operator:t(A, ErrorInfo, A)
    when A :: any(),
         ErrorInfo :: any().
%%--------------------------------------------------------------------
% take(N) when N >= 0 ->
%     Ref = erlang:unique_integer(),
%     ?operator(ItemProducer, St,
%         begin
%             State = add_new_state_field(Ref, N, St),
%             case maps:get(Ref, State, undefined) of
%                 0 -> 
%                     {?COMPLETE, State};
%                 NItem -> % TDOO add condition N is bigger or equal to zero
%                     {Item, NewState} = apply(ItemProducer, [State]),
%                     case observable_item:is_a_next_item(Item) of
%                         true ->
%                             {Item, maps:put(Ref, NItem - 1, NewState)};
%                         false ->
%                             {Item, NewState}
%                     end
%             end
%         end).
take(N) when N >= 0 ->
    % Ref = erlang:unique_integer(),
    ?default_operator(
        fun(?NEXT(Value), State, NewState, StRef) ->
            NItemLeftToTake = maps:get(StRef, State, N),
            case NItemLeftToTake of
                0 -> {?COMPLETE, NewState};
                _ -> {?NEXT(Value), maps:put(StRef, NItemLeftToTake - 1, NewState)}
            end;
           (Item, _State, NewState, _StRef) -> {Item, NewState}
        end
    ).
    % ?operator(ItemProducer, St,
    %     begin
    %         State = add_new_state_field(Ref, N, St),
    %         case maps:get(Ref, State, undefined) of
    %             0 -> 
    %                 {?COMPLETE, State};
    %             NItem -> % TDOO add condition N is bigger or equal to zero
    %                 {Item, NewState} = apply(ItemProducer, [State]),
    %                 case observable_item:is_a_next_item(Item) of
    %                     true ->
    %                         {Item, maps:put(Ref, NItem - 1, NewState)};
    %                     false ->
    %                         {Item, NewState}
    %                 end
    %         end
    %     end).

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
           (Item, _State, NewState, _StRef) -> {Item, NewState}
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
                true  -> {?NEXT(true), mark_observable_as_completed(NewState)};
                false -> {?IGNORE, NewState}
             end;

           (?COMPLETE, _State, NewState, _StRef) ->
                {?NEXT(false), mark_observable_as_completed(NewState)};
            
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
                false -> {?NEXT(false), mark_observable_as_completed(NewState)}
              end;
           (?COMPLETE, _State, NewState, _StRef) ->
                {?NEXT(true), mark_observable_as_completed(NewState)};
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
        (?COMPLETE, State, NewState, StRef) ->
            FinalAcc = maps:get(StRef, State, InitialValue),
            {?NEXT(FinalAcc), mark_observable_as_completed(NewState)};
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
        (?COMPLETE, State, NewState, StRef) ->
            case maps:get(StRef, State, undefined) of
                undefined ->
                    % Complete without any values
                    {?ERROR(no_values), NewState};
                FinalAcc ->
                    % Emit final accumulated value
                    {?NEXT(FinalAcc), mark_observable_as_completed(NewState)}
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
                true -> 
                    {?IGNORE, NewState};
                false -> 
                    NewSeenValues = sets:add_element(Value, SeenValues),
                    {?NEXT(Value), maps:put(StRef, NewSeenValues, NewState)}
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
                UniqueValue -> 
                    {?NEXT(Value), maps:put(StRef, Value, NewState)};
                Value ->
                    % Same as previous value, ignore
                    {?IGNORE, NewState};
                _ -> 
                    % Different from previous value, emit and update
                    {?NEXT(Value), maps:put(StRef, Value, NewState)}
            end;
           (Item, _State, NewState, _StRef) ->
            {Item, NewState}
        end
    ).

%%--------------------------------------------------------------------
-spec flat_map(MapFun) -> operator:t(A, ErrorInfo, B) when
    MapFun :: fun((A) -> observable:t(B, ErrorInfo)),
    A :: any(),
    B :: any(),
    ErrorInfo :: any().
%%--------------------------------------------------------------------
flat_map(MapFun) ->
    ?default_operator(
        fun(?NEXT(Value), State, NewState, StRef) ->
            InnerObservable = MapFun(Value),
            % Get inner producer and merge its state
            #observable{item_producer = InnerProducer} = InnerObservable,
            {InnerItem, InnerState} = apply(InnerProducer, [NewState]),
            % Store inner producer in state if not complete
            case InnerItem of
                ?COMPLETE -> 
                    {?IGNORE, InnerState};
                ?ERROR(_) -> 
                    {InnerItem, InnerState};
                _ ->
                    CurrentInners = maps:get(StRef, State, []),
                    {InnerItem, maps:put(StRef, [InnerProducer|CurrentInners], InnerState)}
            end;
        (?COMPLETE, State, NewState, StRef) ->
            % Try to get more values from inner observables
            case maps:get(StRef, State, []) of
                [] -> {?COMPLETE, NewState};
                [Inner|Rest] ->
                    {InnerItem, InnerState} = apply(Inner, [NewState]),
                    case InnerItem of
                        ?COMPLETE -> 
                            {?HALT, maps:put(StRef, Rest, InnerState)};
                        _ ->
                            {InnerItem, maps:put(StRef, [Inner|Rest], InnerState)}
                    end
            end;
        (Item, _State, NewState, _StRef) ->
            {Item, NewState}
        end
    ).

%%%===================================================================
%%% Internal functions
%%%===================================================================

% %%--------------------------------------------------------------------
% -spec add_new_state_field(Key, Value, State) -> map() when
%     Key :: any(),
%     Value :: any(),
%     State :: map().
% %%--------------------------------------------------------------------
% add_new_state_field(Key, Value, State) ->
%     case maps:get(Key, State, undefined) of
%         undefined ->
%             maps:put(Key, Value, State);
%         _ ->
%             State
%     end.

%%--------------------------------------------------------------------
-spec mark_observable_as_completed(State :: observable:state()) -> map().
%%--------------------------------------------------------------------
mark_observable_as_completed(State) ->
    maps:put(is_completed, true, State).

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
drop_item(Item, _MustDropPred, State, MustDropRef) ->
    {Item, maps:put(MustDropRef, true, State)}.

