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
         filter/1]).

%%%===================================================================
%%% Includes, defines, types and records
%%%===================================================================
-type t(A, ErrorInfo, B) :: fun((observable:item_producer(A, ErrorInfo)) -> observable:t(B, ErrorInfo)).

-define(operator(ItemProducer, State, OpDef),
        fun(ItemProducer) ->
            observable:create(
                fun(State) ->
                    OpDef
                end
            )
        end
).

-define(default_operator_behavior(ItemProducer, Value, St, NewSt, NextNewItem, UpdatedNextSt),
    begin
        {Item, NewSt} = apply(ItemProducer, [St]),
        {
            observable_item:bind(Item, fun(Value) -> NextNewItem end),,
            UpdatedNextSt
        }
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
    fun(ItemProducer) ->
        observable:create(
            fun(State) -> 
                {Item, NewState} = apply(ItemProducer, [State]),
                {observable_item:liftM(MapFun, Item), NewState}
            end
        )
    end.

%%--------------------------------------------------------------------
-spec filter(Pred) -> operator:t(A, ErrorInfo, A)
    when Pred :: fun((A) -> boolean()),
         A    :: any(),
         ErrorInfo :: any().
%%--------------------------------------------------------------------
filter(Pred) ->
    ?operator(ItemProducer, State,
        begin
            {Item, NewState} = apply(ItemProducer, [State]),
            {
                observable_item:bind(Item, fun(Value) ->
                                             case Pred(Value) of
                                                true -> observable_item:create(Value);
                                                false -> observable_item:ignore()
                                             end
                                           end),
                NewState
            }
        end).

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
%                     {complete, State};
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
    Ref = erlang:unique_integer(),
    ?operator(ItemProducer, St,
        begin
            State = add_new_state_field(Ref, N, St),
            case maps:get(Ref, State, undefined) of
                0 -> 
                    {complete, State};
                NItem -> % TDOO add condition N is bigger or equal to zero
                    {Item, NewState} = apply(ItemProducer, [State]),
                    case observable_item:is_a_next_item(Item) of
                        true ->
                            {Item, maps:put(Ref, NItem - 1, NewState)};
                        false ->
                            {Item, NewState}
                    end
            end
        end).

%%--------------------------------------------------------------------
-spec take_while(Pred) -> operator:t(A, ErrorInfo, A) when
    Pred :: fun((A) -> boolean()),
    A :: any(),
    ErrorInfo :: any().
%%--------------------------------------------------------------------
take_while(Pred) ->
    %% double check Haskell's take_while
    ?operator(ItemProducer, State,
        begin
            {Item, NewState} = apply(ItemProducer, [State]),
            {
                observable_item:bind(Item, fun(Value) ->
                                             case Pred(Value) of
                                                true  -> observable_item:create(Value);
                                                false -> observable_item:complete()
                                             end
                                           end),
                NewState
            }
        end).

%%--------------------------------------------------------------------
-spec any(Pred) -> observable_item:t(A, ErrorInfo)
    when
        Pred :: fun((A) -> boolean()),
        A    :: any(),
        ErrorInfo :: any().
%%--------------------------------------------------------------------
any(Pred) ->
    Ref = erlang:unique_integer(),
    ?operator(ItemProducer, State,
        begin
            case maps:get(Ref, State, uncompleted) of
                completed ->
                    {observable_item:complete(), State};
                uncompleted ->
                    {Item, NewState} = apply(ItemProducer, [State]),
                    case Item of
                        complete ->
                            {observable_item:create(false), maps:put(Ref, completed, NewState)};
                        {next, Value} ->
                            case Pred(Value) of
                                true  -> {observable_item:create(true), maps:put(Ref, completed, NewState)};
                                false -> {observable_item:ignore(), maps:put(Ref, uncompleted, NewState)}
                            end;
                        Item ->
                            {Item, NewState}
                    end
            end
        end
    ).

% drop(N) ->
%     Ref = erlang:unique_integer(),
%     ?operator(ItemProducer, State, 
%         begin
%             NItemLeftToDrop = maps:get(Ref, State, N),
%             ?default_operator_behavior(ItemProducer, Item, State, NewState,
%                 case NItemLeftToDrop > 0 of
%                     true ->
%                         observable_item:ignore();
%                     false ->
%                         Item
%                 end,
%                 case observable_item:is_a_next_item(Item) of
%                     true ->
%                         maps:put(Ref, NItemLeftToDrop - 1, NewState);
%                     false ->
%                         maps:put(Ref, NItemLeftToDrop, NewState)
%                 end
%             )
%         end).

%%--------------------------------------------------------------------
-spec drop(N :: non_neg_integer()) -> operator:t(any(), any(), any()).
%%--------------------------------------------------------------------
drop(N) ->
    Ref = erlang:unique_integer(),
    ?operator(ItemProducer, State, 
        begin
            NItemLeftToDrop = maps:get(Ref, State, N),
            {Item, NewState} = apply(ItemProducer, [State]),
            case Item of
                {next, _Value} when NItemLeftToDrop > 0 ->
                    {observable_item:ignore(), maps:put(Ref, NItemLeftToDrop - 1, NewState)};
                Item ->
                    {Item, maps:put(Ref, NItemLeftToDrop, NewState)}
            end
        end).

drop_while(Pred) ->
    %% double check Haskell's take_while
    Ref = erlang:unique_integer(),
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
-spec all(Pred) -> observable_item:t(A, ErrorInfo)
    when
        Pred :: fun((A) -> boolean()),
        A    :: any(),
        ErrorInfo :: any().
%%--------------------------------------------------------------------
all(Pred) ->
    Ref = erlang:unique_integer(),
    ?operator(ItemProducer, State,
        begin
            case maps:get(Ref, State, uncompleted) of
                completed ->
                    {observable_item:complete(), State};
                uncompleted ->
                    {Item, NewState} = apply(ItemProducer, [State]),
                    case Item of
                        complete ->
                            {observable_item:create(true), maps:put(Ref, completed, NewState)};
                        {next, Value} ->
                            case Pred(Value) of
                                true  -> {observable_item:ignore(), maps:put(Ref, uncompleted, NewState)};
                                false -> {observable_item:create(false), maps:put(Ref, completed, NewState)}
                            end;
                        Item ->
                            {Item, NewState}
                    end
            end
        end
    ).

%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
-spec add_new_state_field(Key, Value, State) -> map() when
    Key :: any(),
    Value :: any(),
    State :: map().
%%--------------------------------------------------------------------
add_new_state_field(Key, Value, State) ->
    case maps:get(Key, State, undefined) of
        undefined ->
            maps:put(Key, Value, State);
        _ ->
            State
    end.

drop_item({next, Value} = Item, MustDropPred, State, MustDropRef) ->
    case MustDropPred(Value) of
        true ->
            {observable_item:ignore(), maps:put(MustDropRef,  true, State)};
        false ->
            {Item, maps:put(MustDropRef, false, State)}
    end;
drop_item(Item, _MustDropPred, State, MustDropRef) ->
    {Item, maps:put(MustDropRef, true, State)}.

