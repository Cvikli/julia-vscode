function repl_runcode_request(conn, params::ReplRunCodeRequestParams)
    source_filename = params.filename
    code_line = params.line
    code_column = params.column
    source_code = params.code
    mod = params.mod

    resolved_mod = try
        module_from_string(mod)
    catch err
        # maybe trigger error reporting here
        Main
    end

    show_code = params.showCodeInREPL
    show_result = params.showResultInREPL

    rendered_result = nothing

    hideprompt() do
        if g_use_revise[]
            Revise.revise()
        end
        if show_code
            for (i,line) in enumerate(eachline(IOBuffer(source_code)))
                if i==1
                    printstyled("julia> ", color=:green)
                    print(' '^code_column)
                else
                    # Indent by 7 so that it aligns with the julia> prompt
                    print(' '^7)
                end

                println(line)
            end
        end

        withpath(source_filename) do
            res = try
                ans = Base.invokelatest(include_string, resolved_mod, '\n'^code_line * ' '^code_column *  source_code, source_filename)
                @eval Main ans = $(QuoteNode(ans))
            catch err
                EvalError(err, catch_backtrace())
            end

            if show_result
                if res isa EvalError
                    Base.display_error(stderr, res.err, res.bt)
                elseif res !== nothing && !ends_with_semicolon(source_code)
                    Base.invokelatest(display, res)
                end
            else
                try
                    Base.invokelatest(display, InlineDisplay(), res)
                catch err
                    if !(err isa MethodError)
                        printstyled(stderr, "Display Error: ", color = Base.error_color(), bold = true)
                        Base.display_error(stderr, err, catch_backtrace())
                    end
                end
            end

            rendered_result = safe_render(res)
        end
    end
    return rendered_result
end

function repl_getvariables_request(conn, params::Nothing)
    M = Main
    variables = []
    clear_lazy()

    for n in names(M, all=true, imported=true)
        !isdefined(M, n) && continue
        Base.isdeprecated(M, n) && continue

        x = getfield(M, n)
        x === vscodedisplay && continue
        x === VSCodeServer && continue
        x === Main && continue

        s = string(n)
        startswith(s, "#") && continue
        try
            push!(variables, treerender(SubTree(s, wsicon(x), x)))
        catch err
            printstyled("Internal Error: ", bold = true, color = Base.error_color())
            Base.display_error(err, catch_backtrace())
        end
    end

    return variables
end

function repl_getlazy_request(conn, params::Int)
    res = get_lazy(params)

    return res
end

function repl_showingrid_notification(conn, params::String)
    try
        var = Core.eval(Main, Meta.parse(params))

        Base.invokelatest(internal_vscodedisplay, var)
    catch err
        Base.display_error(err, catch_backtrace())
    end
end

function repl_loadedModules_request(conn, params::Nothing)
    res = string.(collect(get_modules()))

    return res
end

function repl_isModuleLoaded_request(conn, params::String)
    is_loaded = is_module_loaded(params)

    return is_loaded
end

function repl_startdebugger_request(conn, params::String, crashreporting_pipename)
    hideprompt() do
        debug_pipename = params
        try
            DebugAdapter.startdebug(debug_pipename)
        catch err
            DebugAdapter.global_err_handler(err, catch_backtrace(), crashreporting_pipename, "Debugger")
        end
    end
end
