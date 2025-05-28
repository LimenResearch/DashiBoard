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
        "--model_directory"
        help = "directory containing model configuration files"
        arg_type = String
        default = "static/model"
        "--training_directory"
        help = "directory containing training configuration files"
        arg_type = String
        default = "static/training"
        "data_directory"
        help = "directory containing data files"
        required = true
    end

    d = parse_args(ARGS, s)

    return launch(
        d["data_directory"],
        host = d["host"],
        port = d["port"],
        training_directory = d["training_directory"],
        model_directory = d["model_directory"]
    )
end
