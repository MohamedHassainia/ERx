%%%-------------------------------------------------------------------
-module(observable_item).

%% API
-export([create/1,
         bind/2,
         fail/1,
         ignore/0,
         complete/0,
         is_a_next_item/1,
         is_a_complete_item/1,
         get_value_from_next_item/1,
         liftM/2]).

-export_type([t/2]).

%%%===================================================================
%%% Includes, defines, types and records
%%%===================================================================
-type t(A, ErrorInfo) :: {next, A} | {error, ErrorInfo} | ignore | complete.

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec create(Value) -> {next, Value}
    when Value :: any().
%%--------------------------------------------------------------------
create(Value) ->
    {next, Value}.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec fail(ErrorInfo) -> {error, ErrorInfo}
    when ErrorInfo :: any().
%%--------------------------------------------------------------------
fail(ErrorInfo) ->
    {error, ErrorInfo}.


%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec ignore() -> ignore.
%%--------------------------------------------------------------------
ignore() ->
    ignore.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec complete() -> complete.
%%--------------------------------------------------------------------
complete() ->
    complete.

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec bind(ObservableItemA, fun((A) -> ObservableItemB)) -> ObservableItemB
    when A :: any(),
         B :: any(),
         ObservableItemA :: observable_item:t(A, ErrorInfo),
         ObservableItemB :: observable_item:t(B, ErrorInfo),
         ErrorInfo :: any().
%%--------------------------------------------------------------------
bind(ObservableItemA, Fun) ->
    case ObservableItemA of
        {next, Value}      -> apply(Fun, [Value]);
        {error, ErrorInfo} -> {error, ErrorInfo};
        ignore             -> ignore;
        complete           -> complete
    end.

%%--------------------------------------------------------------------
-spec liftM(Fun, ObservableItemA) -> ObservableItemB when
    Fun :: fun((A) -> B),
    ObservableItemA :: observable_item:t(A, ErrorInfo),
    ObservableItemB :: observable_item:t(B, ErrorInfo),
    A :: any(),
    B :: any(),
    ErrorInfo :: any().
%%--------------------------------------------------------------------
liftM(Fun, ObservableItemA) ->
    LiftFun = fun(Value) -> create(apply(Fun, [Value])) end,
    bind(ObservableItemA, LiftFun).

%%--------------------------------------------------------------------
-spec is_a_next_item(observable_item:t(A, ErrorInfo)) -> boolean()
    when A :: any(),
         ErrorInfo :: any().
%%--------------------------------------------------------------------
is_a_next_item({next, _Value}) ->
    true;
is_a_next_item(_) ->
    false.

%%--------------------------------------------------------------------
-spec is_a_complete_item(observable_item:t(A, ErrorInfo)) -> boolean()
    when A :: any(),
         ErrorInfo :: any().
%%--------------------------------------------------------------------
is_a_complete_item(complete) ->
    true;
is_a_complete_item(_) ->
    false.
    
-spec get_value_from_next_item(observable_item:t(A, ErrorInfo)) -> A when
    A :: any(),
    ErrorInfo :: any().

get_value_from_next_item({next, Value}) ->
    Value. 

%%%===================================================================
%%% Internal functions
%%%===================================================================
