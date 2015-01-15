
properties {
	$nunit_executable = ".\BuildAndDeploy\nunit\nunit-console.exe"    
	$build_number = "1.0.0.0"	
	$nugetExe = ".nuget\NuGet.exe"
    $solutionFile = "ReplaceMe.sln"
}

task default -depends Compile, UnitTest

task Compile {	
	CleanNugetPackage
	
	$restore = $nugetExe + " restore $solutionFile"
	Invoke-Expression $restore
	
	msbuild $solutionFile /m /t:Rebuild /p:Configuration=Release /verbosity:quiet /p:RunOctoPack=true /p:VisualStudioVersion=12.0 

	if($lastexitcode -ne 0) {
     	throw "Compile task failed!"
    }	
}

task UnitTest {	
	UnitTest '' "Integration"
}

task IntegrationTest {
	UnitTest "Integration" ""
}

task PackageDeploy {
	msbuild 
}

task DeployDatabase -depends Compile {
	DeployDatabase
}

# deploy using fluent migrations
function DeployDatabase() {
	Set-Location .\database\bin\Release\

	& .\Migrate.exe /assembly database.dll /provider sqlserver2008 /configPath database.dll.config /connection local
}

function UnitTest($includeCategory, $excludeCategory) {
	$testAssemblies = Get-ChildItem .\*Tests*\bin\Release\*Tests.dll | select FullName

	if(!$testAssemblies) {
		return
	}

	$nunitAssemblyList = ""

 	Write-Host "Test: " $excludeCategory

	if($includeCategory -ne "") {
		$includeArgument = "/include:$includeCategory"
	}

	if($excludeCategory -ne "") {
		$excludeArgument = "/exclude:$excludeCategory"	
	}
		
	ForEach($testAssembly in $testAssemblies) {
		$relativePath = $testAssembly.FullName | Resolve-Path -Relative
		$nunitAssemblyList = $nunitAssemblyList + " '" + $relativePath + "'"		
	}

	$test = $nunit_executable + $nunitAssemblyList + "/framework=4.0 /process=multiple /nologo $includeArgument $excludeArgument /domain=multiple /noshadow /err:UnitTestErrors.txt"

	Write-Host "Nunit command to execute: " + $test

	Invoke-Expression $test

	if($lastexitcode -ne 0) {
     	throw "Unit test failed!"
    }	
}

function CleanNugetPackage() {
    # if running octopack you need to clean out the nupkg from the project with octopack installed
	$items = Get-ChildItem -Path *.nupkg -Recurse | ?{$_.fullname -notmatch "\\packages\\?" }

	foreach($item in $items) {
		Remove-Item $item
	}
}
