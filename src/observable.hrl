-ifndef(OBSERVABLE_HRL).
-define(OBSERVABLE_HRL, true).

-type state() :: #{is_completed => boolean()}.
-type item_producer(A, E) :: fun((state()) -> {observable_item:t(A, E), state()}).

-record(observable, {
    state = #{is_completed => false} :: state(),
    item_producer                    :: item_producer(any(), any()),
    subscribers = []                 :: list(subscriber:t(any(), any())),
    pid                              :: undefined | pid()
}).

-type t(A, ErrorInfo) :: #observable{
    state          :: state() | undefined,
    item_producer :: item_producer(A, ErrorInfo),
    subscribers    :: list(subscriber:t(A, ErrorInfo)),
    pid            :: undefined | pid()
}.

-endif.