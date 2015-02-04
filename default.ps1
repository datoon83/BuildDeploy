
properties {
	$nunit_executable = ".\BuildAndDeploy\nunit\nunit-console.exe"    
	$build_number = "1.0.0.0"	
	$nugetExe = ".nuget\NuGet.exe"
    $solutionFile = "ReplaceMe.sln"

    $localDeployPath = "C:\local_sites\"
	$websiteName = "website-replace-me-name"
	$hostHeader = "host.replace.me.name"
	$locationOfNugetPackageToDeploy = "place-to-find-nuget-package\bin"

	$shouldDeployDatabase = $false
	$DatabaseProjectName = "database-project-name"
}

task default -depends Compile, UnitTest

task Compile {	
	CleanNugetPackage
	
	$restore = $nugetExe + " restore $solutionFile -NoCache"
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

task Deploy -depends Compile, UnitTest {
	if($shouldDeployDatabase -eq $true) {
		DeployDatabase
	}
	DeploySite
}

# Deploys website to specific location - with an app pool of the same name (currently .Net 4) - only works with WebAdministration tools installed
# Adds a host entry for the given name of the site
function DeploySite() {
	Import-Module WebAdministration

	$deployLocation = $localDeployPath + $websiteName

	if((Test-Path -Path $localDeployPath) -eq $false)
	{
		New-Item $localDeployPath -ItemType Directory
		"Created $localDeployPath"
	}

	if((Test-Path -Path $deployLocation) -eq $false)
	{
		New-Item $deployLocation -ItemType Directory
		"Created $deployLocation"
	}
	else {
	    Remove-Item "$deployLocation\*" -Force -Recurse
	    "Removed files from $deployLocation"
	}
	
	$nugetPackage = Get-ChildItem -Path $locationOfNugetPackageToDeploy -Recurse -Include *.nupkg
	"Found $nugetPackage to copy"

	Copy-Item -Path $nugetPackage -Destination $deployLocation -Force
	"Copied $nugetPackage to $deployLocation"

	Dir $deployLocation | rename-item -newname {  $_.name  -replace ".nupkg",".zip"  }
	"Renamed .nupkg to .zip"

	extract-nuget-package $deployLocation $nugetPackage

	if(Test-Path IIS:\AppPools\$websiteName)
	{
		Remove-WebAppPool -Name $websiteName
		"$websiteName already exists - removed"
	} 

	New-WebAppPool -Name $websiteName
	Set-ItemProperty IIS:\AppPools\$websiteName managedRuntimeVersion v4.0
	"Created app pool $websiteName"

	New-Website -Name $websiteName -Port 80 -HostHeader $hostHeader -ApplicationPool $websiteName -PhysicalPath $deployLocation -Force
	Start-Website -Name $websiteName
	"Started $websiteName"

	$file = "C:\Windows\System32\drivers\etc\hosts"
	add-host $file "127.0.0.1" $hostHeader
	"Added host entry $hostHeader"
}

function extract-nuget-package($deployLocation, $nugetPackage) {
	$shell = New-Object -com Shell.Application

	$zipToUndo = $deployLocation + "\" + $nugetPackage.Name.Replace(".nupkg", ".zip")
	$zip = $shell.NameSpace($zipToUndo)
	ForEach($item in $zip.items())
	{
		$shell.Namespace($deployLocation).copyhere($item)
	}
	"extracted $nugetPackage to $deployLocation"
}

function add-host([string]$filename, [string]$ip, [string]$hostname) {
	remove-host $filename $hostname
	$ip + "`t`t" + $hostname | Out-File -encoding ASCII -append $filename
}

function remove-host([string]$filename, [string]$hostname) {
	$c = Get-Content $filename
	$newLines = @()
	
	foreach ($line in $c) {
		$bits = [regex]::Split($line, "\t+")
		if ($bits.count -eq 2) {
			if ($bits[1] -ne $hostname) {
				$newLines += $line
			}
		} else {
			$newLines += $line
		}
	}
	
	# Write file
	Clear-Content $filename
	foreach ($line in $newLines) {
		$line | Out-File -encoding ASCII -append $filename
	}
}

# deploy using fluent migrations
function DeployDatabase() {
	$currentLocation = Get-Location
	Set-Location ".\$DatabaseProjectName\bin\Release\" 

	$migrationToRun = ".\Migrate.exe /assembly $DatabaseProjectName.dll /provider sqlserver2008 /configPath $DatabaseProjectName.dll.config /connection local"
	Invoke-Expression $migrationToRun

	Set-Location $currentLocation
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
		if($item -ne $null) {
			Remove-Item $item
		}
	}
}
