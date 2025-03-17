%%%-------------------------------------------------------------------
%%% @doc
%%% Subscriber module for handling reactive stream events.
%%% Implements the Observer pattern where subscribers receive next/error/complete events.
%%% @end
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
-include("subscriber.hrl").

-type t(A, E) :: #subscriber{
    on_next :: on_next(A),
    on_error :: on_error(E),
    on_complete :: on_complete()
}.

-type on_next(A)    :: fun((A) -> any()). 
-type on_error(ErrorInfo)   :: fun((ErrorInfo) -> any()). 
-type on_complete() :: fun(() -> any()). 
-type callback_fun(A, ErrorInfo) :: on_next(A) | on_error(ErrorInfo) | on_complete() | undefined.

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Creates a basic subscriber with just an OnNext callback
%% OnNext is called whenever a new value is emitted in the stream
%% @param OnNext The callback function to handle next values
%% @returns A new subscriber record
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
%% @doc Creates a full subscriber with all callbacks
%% @param OnNext The callback for next values 
%% @param OnError The callback for error events
%% @param OnComplete The callback for stream completion
%% @returns A new subscriber record with all callbacks set
%% @end
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
%% @doc Creates a full subscriber with the following callbacks
%% @param OnNext The callback for next values 
%% @param OnError The callback for error events
%% @returns A new subscriber record with all callbacks set
%% @end
%%--------------------------------------------------------------------
-spec create(OnNext, OnError) -> t(A, ErrorInfo) when
    OnNext     :: on_next(A),
    OnError    :: on_error(ErrorInfo),
    A :: any(),
    ErrorInfo :: any().
%%--------------------------------------------------------------------
create(OnNext, OnError) ->
    #subscriber{on_next = OnNext, on_error =  OnError}.

%%--------------------------------------------------------------------
%% @doc Retrieves a specific callback function from a subscriber
%% @param CallbackFunName Which callback to get (on_next|on_error|on_complete) 
%% @param Subscriber The subscriber record
%% @returns The requested callback function or undefined
%% @end
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
        ?ON_NEXT when OnNext /= undefined -> OnNext;
        ?ON_COMPLETE -> OnComplete;
        ?ON_ERROR -> OnError
    end.

%%%===================================================================
%%% Internal functions
%%%===================================================================
