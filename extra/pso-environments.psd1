@{
    # One key per PSO environment. The key name is what you pass to -Environment
    # (and is also what's used to build the PSO_PWD_<Environment> env var name
    # for the password - see -StorePassword in the script's help).
    #
    # No passwords in this file - those live in PSO_PWD_<Environment> env vars,
    # set via -StorePassword or [Environment]::SetEnvironmentVariable(...). This
    # file only holds connection info, so it's safe to commit alongside the script.

    theDrome = @{
        GatewayBaseUrl = "https://pso.thetechnodro.me/IFSSchedulingRESTfulGateway/api/v1"
        AccountId      = "Default"
        UserId         = "INT_USER"
    }

    saskTST = @{
        GatewayBaseUrl = "https://sast-pso-tst.ifs.cloud/IFSSchedulingRESTfulGateway/api/v1"
        AccountId      = "sate"
        UserId         = "GOGH_INT"
    }


    # Add more environments here as needed, e.g.:
    # conocoUat = @{
    #     GatewayBaseUrl = "https://pso-uat.example.com/IFSSchedulingRESTfulGateway/api/v1"
    #     AccountId      = "Default"
    #     UserId         = "INT_USER"
    # }
}
