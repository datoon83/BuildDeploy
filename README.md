# BuildDeploy

Just a template for Visual Studio build and package

Uses:
- pSake
- NUnit version (2.6.4)

Runs:
- OctoPack if installed on a .csproj

By Default running "psake.cmd" - from the root of the solution will build and unit test only

Running "psake.cmd Deploy" will deploy database if configured using fluent migrations & deploy IIS website

IIS 7 and all the gumpf that is needed for that is required!
