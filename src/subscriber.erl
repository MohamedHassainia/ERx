%%%-------------------------------------------------------------------
-module(subscriber).

%% API
-export([create/1,
         get_callback_function/2,
         create/3]).

-export_type([t/2,
              on_next/1,
              on_error/1,
              on_complete/0]).

%%%===================================================================
%%% Includes, defines, types and records
%%%===================================================================
-record(subscriber,{
    on_next :: fun((any()) -> any()),
    on_error :: fun((any()) -> any()) | undefined,
    on_complete :: fun(() -> any()) | undefined
}).

-type t(A, E) :: #subscriber{
    on_next :: on_next(A),
    on_error :: on_error(E) | undefined,
    on_complete :: on_complete() | undefined
}.

-type on_next(A)    :: fun((A) -> any()).
-type on_error(ErrorInfo)   :: fun((ErrorInfo) -> any()).
-type on_complete() :: fun(() -> any()).
-type callback_fun(A, ErrorInfo) :: on_next(A) | on_error(ErrorInfo) | on_complete() | undefined.

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
-spec create(OnNext) -> t(A, ErrorInfo) when
    OnNext :: on_next(A),
    A :: any(),
    ErrorInfo :: any().
%%--------------------------------------------------------------------
create(OnNext) ->
    #subscriber{on_next = OnNext}.

%%--------------------------------------------------------------------
-spec create(OnNext, OnError, OnComplete) -> t(A, ErrorInfo) when
    OnNext     :: on_next(A),
    OnError    :: on_error(ErrorInfo),
    OnComplete :: on_complete(),
    A :: any(),
    ErrorInfo :: any().
%%--------------------------------------------------------------------
create(OnNext, OnError, OnComplete) ->
    #subscriber{on_next = OnNext, on_error =  OnError, on_complete = OnComplete}.

%%--------------------------------------------------------------------
-spec get_callback_function(CallbackFunName, Subscriber) -> callback_fun(A, ErrorInfo) when
    CallbackFunName :: on_next | on_error | on_complete,
    Subscriber      :: subscriber:t(A, ErrorInfo),
    A               :: any(),
    ErrorInfo       :: any().
%%--------------------------------------------------------------------
get_callback_function(CallbackFunName, Subscriber) ->
    #subscriber{on_next = OnNext, on_complete = OnComplete, on_error = OnError} = Subscriber,
    case CallbackFunName of
        on_next when OnNext /= undefined -> OnNext;
        on_complete -> OnComplete;
        on_error -> OnError
    end.

%%%===================================================================
%%% Internal functions
%%%===================================================================
