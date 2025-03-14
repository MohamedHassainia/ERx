-module(observable_manager).

-export([halt_observable/2,
         resume_observable/1,
         resume_observable/3]).
-define(observables_table, observables_table).
-include("observable.hrl").

%====================================================================
% API functions
%====================================================================
-spec halt_observable(Observable :: observable:t(any(), any()), Ref :: integer()) -> ok.
halt_observable(Observable, Ref) ->
    ets:insert(?observables_table, {Ref, Observable}).

resume_observable(ObservableRef, QueueRef, Item) ->
    [Observable] = ets:match_object(?observables_table, {ObservableRef, '_'}),
    NewObservable = add_to_queue(Observable, QueueRef, Item),
    observable:run(NewObservable, ObservableRef).

resume_observable(ObservableRef) ->
    [Observable] = ets:match_object(?observables_table, {ObservableRef, '_'}),
    observable:run(Observable, ObservableRef).

add_to_queue(#observable{state = State} = Observable, QueueRef, Item) ->
    case maps:get(QueueRef, State) of
        undefined ->
            State1 = maps:put(QueueRef, [Item], State),
            Observable#observable{state = State1};
        Queue ->
            State1 = maps:put(QueueRef, Queue ++ [Item], State),
            Observable#observable{state = State1}
    end.

