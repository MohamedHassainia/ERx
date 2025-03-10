-ifndef(OBSERVABLE_HRL).
-define(OBSERVABLE_HRL, true).

-type state() :: #{is_completed => boolean()}.
-type item_producer(A, E) :: fun((state()) -> {observable_item:t(A, E), state()}).

-record(gen_server_options, {
    timeout     = infinity :: integer() | infinity,
    buffer_size = 10000 :: integer()
}).

-record(observable, {
    state = #{is_completed => false}           :: state(),
    item_producer                              :: item_producer(any(), any()),
    subscribers = []                           :: list(subscriber:t(any(), any())),
    async = false                              :: boolean(),
    gen_server_options = #gen_server_options{} :: #gen_server_options{},
    pid                                        :: undefined | pid()
}).

-type t(A, ErrorInfo)  :: #observable{
    state              :: state() | undefined,
    item_producer      :: item_producer(A, ErrorInfo),
    subscribers        :: list(subscriber:t(A, ErrorInfo)),
    async              :: boolean(),
    gen_server_options :: #gen_server_options{},
    pid                :: undefined | pid()
}.

-endif.