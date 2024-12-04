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
        "data_directory"
        help = "directory containing data files"
        required = true
    end

    d = parse_args(ARGS, s)

    launch(d["data_directory"], host = d["host"], port = d["port"])
end
