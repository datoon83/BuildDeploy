
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
	$databaseInstanceName = "database-instance-name"

	$jmeter = "D:\tools\JMeter\apache-jmeter-2.12\bin\jmeter"
    $jMeterCMDRunner = "D:\tools\JMeter\apache-jmeter-2.12\lib\ext\CMDRunner.jar"
    
    $testPlan = ".\JMeter\Load-Test.jmx"
    $reportNamePrefix = Get-Date
    $reportFileName = "\test-result.jtl"

    $relativeReportLocation = "./load-test-results/"

	if((Test-Path -Path $relativeReportLocation) -eq $false) {
		New-Item $relativeReportLocation -ItemType Directory
	}

	$reportLocation = Resolve-Path -Path $relativeReportLocation
	$jtlReportLocation =  $reportLocation.Path + $reportFileName
}

task default -depends Compile, UnitTest

task LoadTest -depends RunLoadTest, MakeLoadTestGraph, MakeLoadTestCsv, CreateHtmlReport

task RunLoadTest {
	
	$jtlReportLocation

	cmd.exe /c $jmeter -n -t $testPlan -l $jtlReportLocation | ForEach-Object {
	    $line = $_

	    if($line -match "^Waiting for possible shutdown message on port ([0-9]+)") {
	        Write-Host "Running load test: $testPlan"
	        $jMeterListenerPort = $matches[1];
	        return;
	    }
	}
}

task CreateHtmlReport {
	$xslt = New-Object System.Xml.Xsl.XslCompiledTransform

	$xsl = ".\JMeter\jmeter-results-report.xsl"
	$xml = $jtlReportLocation
	$output = $reportLocation.Path + "/loadReport.html"

	$xslt.Load($xsl);
	$xslt.Transform($xml, $output)

	[xml]$results = Get-Content $jtlReportLocation

	$anyFailed = $results.testResults | %{$_.httpSample.s -eq $false}
	$allTotalTime = $results.testResults | %{ ($_.httpSample | Measure-Object -Property t -Sum).Sum }
	$allCount = $results.testResults.httpSample.Length
	$average = $allTotalTime / $allCount

	$numberOfFailedTest = $anyFailed.Count

	"Average time to execute tests $average ms"
	"Number of failed tests $numberOfFailedTest"

	if($numberOfFailedTest -ne 0) {
		throw "Too many failed performance tests $numberOfFailedTest"
	}
}

task MakeLoadTestGraph {
    $jMeterReportNameDatePrefix = FormatFileNameFriendlyDate($reportNamePrefix)
 
    & java.exe -jar $jMeterCMDRunner --tool Reporter --generate-png "$reportLocation\$jMeterReportNameDatePrefix-graph.png" --input-jtl $jtlReportLocation --plugin-type ResponseTimesOverTime --width 800 --height 600
}

task MakeLoadTestCSV {
    $jMeterReportNameDatePrefix = FormatFileNameFriendlyDate($reportNamePrefix)
 
    & java.exe -jar $jMeterCMDRunner --tool Reporter --generate-csv "$reportLocation\$jMeterReportNameDatePrefix-details.csv" --input-jtl $jtlReportLocation --plugin-type AggregateReport 

    & java.exe -jar $jMeterCMDRunner --tool Reporter --generate-csv "$reportLocation\$jMeterReportNameDatePrefix-response-times.csv" --input-jtl $jtlReportLocation --plugin-type ResponseTimesOverTime 

	& java.exe -jar $jMeterCMDRunner --tool Reporter --generate-csv "$reportLocation\$jMeterReportNameDatePrefix-synthesis-report.csv" --input-jtl $jtlReportLocation --plugin-type SynthesisReport  	
}

function FormatFileNameFriendlyDate($dateTime)
{
        $formatedDate = $dateTime.ToUniversalTime().ToString("u") 
        $formatedDate = $formatedDate.Replace(" ", "_")
        $formatedDate = $formatedDate.Replace(":", "-")
        return $formatedDate
}

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

task Deploy -depends Compile, UnitTest {
	DeploySite

	if($shouldDeployDatabase -eq $true) {
		DeployDatabase
	}
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

	CreateDatabase

	Set-Location $currentLocation

	$currentLocation = Get-Location
	Set-Location ".\$DatabaseProjectName\bin\Release\" 

	$migrationToRun = ".\Migrate.exe /assembly $DatabaseProjectName.dll /provider sqlserver2008 /configPath $DatabaseProjectName.dll.config /connection local"
	Invoke-Expression $migrationToRun

	Set-Location $currentLocation

	CreateDatabaseUser
}

function CreateDatabase()
{
	Import-Module "sqlps" -DisableNameChecking

	$smo = New-Object Microsoft.SqlServer.Management.Smo.Server $env:ComputerName

	if($smo.databases.item($databaseInstanceName) -eq $null)
	{
		"db doesn't exist"
		$db = New-Object Microsoft.SqlServer.Management.Smo.Database($smo, $databaseInstanceName)
		$db.create()	
		"db created $databaseInstanceName"
	}
}

function CreateDatabaseUser() 
{
	Import-Module "sqlps" -DisableNameChecking

	$smo = New-Object Microsoft.SqlServer.Management.Smo.Server $env:ComputerName

	$sqlUserName = "IIS APPPOOL\$websiteName"

	if ($smo.logins.Name -like "*$websiteName*") {
		"sql user does exist"
	} else {
		"user does not exist"

	    $login = new-object Microsoft.SqlServer.Management.Smo.Login($env:ComputerName, $sqlUserName)
		$login.LoginType = 'WindowsUser'
		$login.PasswordPolicyEnforced = $false
		$login.PasswordExpirationEnabled = $false
		$login.Create()

		"created user on instance $env:ComputerName with username $sqlUserName"

		$db = $smo.databases.item($databaseInstanceName)

		$usr = New-Object Microsoft.SqlServer.Management.Smo.User($db, $sqlUserName)
		$usr.Login = $sqlUserName
		$usr.Create()

		"created user on database $db with username $sqlUserName"

		foreach($role in $db.roles) {
			if($role.name -eq 'db_datareader') {
				$role.AddMember($sqlUserName)
				"added sql user to role db_datareader"
			}

			if($role.name -eq 'db_datawriter') {
				$role.AddMember($sqlUserName)
				"added sql user to role db_datawriter"
			}
		}
	}
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
