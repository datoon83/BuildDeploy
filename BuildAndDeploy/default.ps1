Properties {}

Task default -Depends build, test, publish

Task build {
    Invoke-psake Solution.Compile.ps1
}

Task test {
     #Invoke-psake Solution.Test.ps1
}

Task publish {
     Invoke-psake Solution.Publish.ps1
}