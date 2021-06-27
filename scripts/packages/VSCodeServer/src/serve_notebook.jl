const stdio_bytes = Ref(0)

const orig_stdin  = Ref{IO}()
const orig_stdout = Ref{IO}()
const orig_stderr = Ref{IO}()

const read_stdout = Ref{Base.PipeEndpoint}()
const read_stderr = Ref{Base.PipeEndpoint}()

const capture_stdout = true
const capture_stderr = true

const notebook_runcell_request_type = JSONRPC.RequestType("notebook/runcell", NamedTuple{(:code,),Tuple{String}}, NamedTuple{(:success, :error),Tuple{Bool,NamedTuple{(:message, :name, :stack),Tuple{String,String,String}}}})

function notebook_runcell_request(conn, params::NamedTuple{(:code,),Tuple{String}})
    decoded_msg = params.code

    try
        result = Base.invokelatest(include_string, Main, decoded_msg, "FOO")

        flush_all()

        if result !== nothing
            Base.invokelatest(Base.display, result)
        end

        flush_all()

        return (success = true, error = (message = "", name = "", stack = ""))
    catch err
        bt = catch_backtrace()

        if err isa LoadError
            inner_err = err.error

            st = stacktrace(bt)

            error_type = string(typeof(inner_err))
            error_message_str = sprint(showerror, inner_err)
            traceback = sprint(Base.show_backtrace, bt)

            return (success = false, error = (message = error_message_str, name = error_type, stack = traceback))
        else
            rethrow(err)
            error("Not clear what this means, but we should probably send a crash report.")
        end
    end
end

function serve_notebook(pipename; crashreporting_pipename::Union{AbstractString,Nothing}=nothing)
    conn = Sockets.connect(pipename)

    conn_endpoint[] = JSONRPC.JSONRPCEndpoint(conn, conn)

    run(conn_endpoint[])

    orig_stdin[]  = Base.stdin
    orig_stdout[] = Base.stdout
    orig_stderr[] = Base.stderr

    try
        if capture_stdout
            read_stdout[], = Base.redirect_stdout()
            redirect_stdout(JuliaNotebookStdio(Base.stdout, "stdout"))
        end
        if capture_stderr
            read_stderr[], = redirect_stderr()
            redirect_stderr(JuliaNotebookStdio(Base.stderr, "stderr"))
        end
        redirect_stdin(JuliaNotebookStdio(Base.stdin, "stdin"))

        Base.Multimedia.pushdisplay(JuliaNotebookInlineDisplay())

        watch_stdio()

        msg_dispatcher = JSONRPC.MsgDispatcher()
        msg_dispatcher[notebook_runcell_request_type] = notebook_runcell_request
        msg_dispatcher[repl_getvariables_request_type] = repl_getvariables_request
        msg_dispatcher[repl_getlazy_request_type] = repl_getlazy_request
        msg_dispatcher[repl_showingrid_notification_type] = repl_showingrid_notification

        println(orig_stdout[], "Julia Kernel started...")

        while true
            msg = JSONRPC.get_next_message(conn_endpoint[])

            JSONRPC.dispatch_msg(conn_endpoint[], msg_dispatcher, msg)
        end

    catch err
        Base.display_error(orig_stderr[], err, catch_backtrace())
        readline()
    end

end
