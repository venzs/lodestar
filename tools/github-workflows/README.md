Copies of `.github/workflows/*.yml`. The remote file bridge refuses to write into `.github/workflows`,
so if that folder is missing in your checkout, move these two files there:

    mkdir .github\workflows
    move tools\github-workflows\ci.yml .github\workflows\
    move tools\github-workflows\release.yml .github\workflows\
