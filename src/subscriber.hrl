-ifndef(SUBSCRIBER_HRL).
-define(SUBSCRIBER_HRL, true).

-include("observable_item.hrl").
-include("subscriber.hrl").

-define(ON_NEXT, on_next).
-define(ON_ERROR, on_error).
-define(ON_COMPLETE, on_complete).

-define(default_error_handler, fun(ErrorInfo) -> ErrorInfo end).

-define(default_complete_handler, fun() -> completed end).

-record(subscriber,{
    on_next :: fun((any()) -> any()),
    on_error = ?default_error_handler :: fun((any()) -> any()),
    on_complete  = ?default_complete_handler :: fun(() -> any())
}).

-endif.
