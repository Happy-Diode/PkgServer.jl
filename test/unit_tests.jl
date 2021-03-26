@testset "GitHub REST API URLs" begin
    import PkgServer.GitHub

    owner = "SomeOrg"
    repo = "PrivateRegistry"
    expected_api_repo_url = "https://api.github.com/repos/$owner/$repo"

    # repository URL must be specified with or without ".git" suffix
    @test GitHub.api_repository_url("https://github.com/$owner/$repo.git") == expected_api_repo_url
    @test GitHub.api_repository_url("https://github.com/$owner/$repo") == expected_api_repo_url

    # repository URL must be root
    @test_throws DomainError GitHub.api_repository_url("https://github.com/JuliaRegistries/General/tree/master/")

    # only GitHub-hosted repos are supported
    @test_throws DomainError GitHub.api_repository_url("https://gitlab.com/$owner/$repo")
    @test_throws DomainError GitHub.api_repository_url("https://git.example.com/$owner/$repo")

    # tree SHA URL
    sha = "46e44e869b4d90b96bd8ed1fdcf32244fddfb6cc"
    @test GitHub.api_tree_url(expected_api_repo_url, sha) == expected_api_repo_url * "/git/trees/$sha"
end

@testset "GitHub.resource_exists()" begin
    import PkgServer.GitHub
    import HTTP
    using SimpleMock

    anyvalue = Predicate(_ -> true)

    api_resource_url = "https://api.github.com/repos/SomeOrg/SomeRepo"
    token = "simulated_token"

    http_ok = HTTP.Response(200)

    mock(HTTP.request => Mock((args...; kwargs...) -> http_ok)) do _request
        # resource_exists() without token makes a HEAD request without Authorization header
        @test GitHub.resource_exists(api_resource_url) == true
        @test called_once_with(_request, "HEAD", api_resource_url, []; status_exception=false)

        reset!(_request)

        # resource_exists() with token makes a HEAD request with Authorization header
        @test GitHub.resource_exists(api_resource_url, token=token) == true
        @test called_once_with(_request, "HEAD", api_resource_url, ["Authorization" => "token $token"]; status_exception=false)
    end

    http_not_found = HTTP.Response(404)

    mock(HTTP.request => Mock((args...; kwargs...) -> http_not_found)) do _request
        # non-200 response indicates resource does not exist
        @test GitHub.resource_exists(api_resource_url) == false
        @test GitHub.resource_exists(api_resource_url; token=token) == false
    end
end

@testset "RegistryMeta constructor" begin 
    import PkgServer.GitHub, PkgServer.RegistryMeta
    import HTTP
    using SimpleMock

    owner = "SomeOrg"
    repo = "SomeRepo"
    token = "simulated_token"

    url_nogitsuffix = "https://github.com/$owner/$repo"
    url_gitsuffix = "https://github.com/$owner/$repo.git"

    expected_api_repo_url = "https://api.github.com/repos/$owner/$repo"

    http_ok = HTTP.Response(200)

    mock(HTTP.request => Mock((args...; kwargs...) -> http_ok)) do _request
        #
        # simulate a public registry that does not require an access token
        #

        meta1 = RegistryMeta(url_nogitsuffix)
        @test meta1.upstream_url == url_nogitsuffix
        @test meta1.upstream_api_url == expected_api_repo_url
        @test meta1.access_token === nothing

        # repo checked for accessibility without token
        @test called_once_with(_request, "HEAD", expected_api_repo_url, []; status_exception=false)

        reset!(_request)

        meta2 = RegistryMeta(url_gitsuffix)
        @test meta2.upstream_url == url_gitsuffix
        @test meta2.upstream_api_url == expected_api_repo_url
        @test meta2.access_token === nothing
        
        # repo checked for accessibility without token
        @test called_once_with(_request, "HEAD", expected_api_repo_url, []; status_exception=false)

        #
        # simulate a private registry with a specified access token
        #

        reset!(_request)

        meta3 = RegistryMeta(url_nogitsuffix, token=token)
        @test meta3.upstream_url == url_nogitsuffix
        @test meta3.upstream_api_url == expected_api_repo_url
        @test meta3.access_token === token 

        # repo checked for accessibility with token
        @test called_once_with(_request, "HEAD", expected_api_repo_url, ["Authorization" => "token $token"]; status_exception=false)

        reset!(_request)

        meta4 = RegistryMeta(url_gitsuffix, token=token)
        @test meta4.upstream_url == url_gitsuffix
        @test meta4.upstream_api_url == expected_api_repo_url
        @test meta4.access_token === token 

        # repo checked for accessibility with token
        @test called_once_with(_request, "HEAD", expected_api_repo_url, ["Authorization" => "token $token"]; status_exception=false)
    end

    http_not_found = HTTP.Response(404)

    mock(HTTP.request => Mock((args...; kwargs...) -> http_not_found)) do _request
        # GitHub API returns a 404 if a URL references a known registry but the token is invalid
        # TODO: is DomainError more appropriate since this is not a signature mismatch but an invalid value?
        @test_throws ArgumentError RegistryMeta(url_gitsuffix, token=token)
    end
end