using ArgParse: ArgParseSettings, @add_arg_table!, parse_args
using DashiBoard: launch

function (@main)(ARGS)
    s = ArgParseSettings()
    @add_arg_table! s begin
        "--host"
        help = "url hosting the server"
        arg_type = String
        default = "127.0.0.1"
        "--port"
        help = "port number"
        arg_type = Int
        default = 8080
    end

    parsed_args = parse_args(ARGS, s)

    launch(host = parsed_args["host"], port = parsed_args["port"])
end
