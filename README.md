# BuildDeploy

Just a template for Visual Studio build and package.

Deploy locally with IIS and FluentMigrator

Also runs load tests and creates specific html reports from the output - requires JMeter

Uses:
- pSake
- NUnit version (2.6.4)
- JMeter version (2.12)

Runs:
- OctoPack if installed on a .csproj

By Default running "psake.cmd" - from the root of the solution will build and unit test only

Running "psake.cmd Deploy" will deploy database if configured using fluent migrations & deploy IIS website

IIS 7 and all the gumpf that is needed for that is required!
