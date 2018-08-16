# Bootstrap a fresh "Windows Server 1709 Docker" OS

param
(
    [Parameter(Mandatory=$true)]
    [uint32] [ValidateRange(1,256)] $numberOfAgents
)

$Error.Clear()
$LastExitCode = 0

# Rename machine name.
# Server machine should be name as Everest-BuildServer-Windows
if ($env:COMPUTERNAME -ne "Everest-Win-Bld") {
    Write-Host "Machine needs to be renamed and a restart is required."
    Write-Host "Restarting machine, please re-run script once it is back."
    Start-Sleep -Seconds 10
    Rename-Computer -NewName "Everest-Win-Bld" -Force -Restart -Confirm:$false
}

$ProgressPreference = 'SilentlyContinue'
Write-Host "==== Bootstrap ===="

# powershell defaults to TLS 1.0, which many sites don't support.  Switch to 1.2.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# create /home/builder/build if needed
$build_dir = "/home/builder/build"
mkdir -Force $build_dir | Out-Null
Set-Location $build_dir

# install dotnet core
Write-Host "Install dotnetCore if not present."
$dotnetCoreExists = (Get-Command dotnet -ErrorAction:SilentlyContinue)
if ($null -eq $dotnetCoreExists) {
    $Error.Clear()

    # Download script to install dotnet runtime
    Write-Host "Download dotnet core install script."
    wget "https://dot.net/v1/dotnet-install.ps1" -outfile "dotnet-install.ps1"
    Write-Host "Installing dotnet core pre-reqs"
    ./dotnet-install.ps1
    Remove-Item "dotnet-install.ps1"

    if ($Error.Count -gt 0 -or $LastExitCode -ne 0) {
        $Error
        return
    }

    # Now that all dependencies of dotnet core are installed install dontnet core sdk 2.0
    Write-Host "Download and Install dotnetCore SDK"
    wget "https://download.microsoft.com/download/9/D/2/9D2354BE-778B-42D6-BA4F-3CEF489A4FDE/dotnet-sdk-2.1.400-win-x64.exe" -outfile "dotnet_sdk_setup.exe"
    Start-Process dotnet_sdk_setup.exe -Wait -ArgumentList "-q"
    Remove-Item "dotnet_sdk_setup.exe"

    if ($Error.Count -gt 0 -or $LastExitCode -ne 0) {
        $Error
        return
    }
}

Write-Host "Install Azure CLI if not present."
$azExists = (Get-Command az -ErrorAction:SilentlyContinue)
if ($null -eq $azExists) {
    $Error.Clear()

    # install azure CLI
    Write-Host "Installing Azure CLI"
    wget "https://aka.ms/installazurecliwindows" -outfile "azurecli.msi"
    Start-Process msiexec.exe -Wait -ArgumentList "/i azurecli.msi /passive"
    Remove-Item "azurecli.msi"

    if ($Error.Count -gt 0 -or $LastExitCode -ne 0) {
        $Error
        return
    }
}

#install git
Write-Host "Install GIT if not present."
$gitExists = (Get-Command git -ErrorAction:SilentlyContinue)
if ($null -eq $gitExists) {
    $Error.Clear()

    Write-Host "Installing Git"
    wget "https://github.com/git-for-windows/git/releases/download/v2.17.1.windows.2/Git-2.17.1.2-64-bit.exe" -outfile "git_setup.exe"
    Start-Process git_setup.exe -Wait -ArgumentList "/SILENT /NORESTART /DIR=c:\Git"
    Remove-Item "git_setup.exe"

    if ($Error.Count -gt 0 -or $LastExitCode -ne 0) {
        $Error
        return
    }
}

#install docker-machine
Write-Host "Install Docker if not present."
$dockerExists = (Get-Command docker -ErrorAction:SilentlyContinue)
if ($null -eq $dockerExists) {
    Write-Host "Installing Docker"
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    Install-Module -Name DockerMsftProvider -Force
    Install-Package -Name docker -ProviderName DockerMsftProvider -Force

    Write-Host "Restarting machine, please re-run script once it is back."
    Start-Sleep -Seconds 10
    Restart-Computer -Force
}

if ((Test-Path "C:\ProgramData\Docker\config\daemon.json") -eq $false) {
    # The VSTS agents run as NetworkService, which has little local access to the machine.
    # The Docker service's named pipe defaults to only allowing admin users.  So bridge the
    # two via a group called "docker"
    net localgroup docker /add
    net localgroup docker NetworkService /add
    Add-Content -Path C:\ProgramData\Docker\config\daemon.json -Value '{ "group" : "docker" }' -Encoding Ascii

    Stop-Service docker
    Start-Service docker
    $Error.Clear()
}

if ($Error.Count -gt 0 -or $LastExitCode -ne 0) {
    $Error
    return
}

#install node.js
Write-Host "Install Node.js if not present."
$nodeExists = (Get-Command npm -ErrorAction:SilentlyContinue)
if ($null -eq $nodeExists) {
    Write-Host "Installing Node.js"
    wget https://nodejs.org/dist/v8.11.2/node-v8.11.2-x64.msi -outfile "node_setup.msi"
    Start-Process msiexec.exe -Wait -ArgumentList "/i node_setup.msi INSTALLDIR=c:\Node /passive"
    Remove-Item "node_setup.msi"

    Write-Host "Restarting machine, please re-run script once it is back."
    Start-Sleep -Seconds 10
    Restart-Computer -Force
}

Write-Host "Install TypeScript if not present."
$tscExists = (Get-Command tsc -ErrorAction:SilentlyContinue)
if ($null -eq $tscExists) {
    # Install typescript
    Write-Host "Installing TypeScript"
    npm install -g typescript

    if ($Error.Count -gt 0 -or $LastExitCode -ne 0) {
        $Error
        return
    }
}

# create /home/builder/build/agents
$agents_dir = "$($(Get-Location).Path)\agents"
mkdir -Force $agents_dir | Out-Null

# download the VSTS windows agent to that directory
write-host "Downloading VSTS Windows Agent"
wget "https://vstsagentpackage.azureedge.net/agent/2.134.2/vsts-agent-win-x64-2.134.2.zip" -outfile "$agents_dir\vsts-agent.zip"

Add-Type -AssemblyName System.IO.Compression.FileSystem

# for each in $numberOfAgents
#  create agent-# subdir
#  copy the agent binary into the subdir and extract from the downloaded .zip
for ($i=1; $i -le $numberOfAgents; $i++) {
  $agent = "$((Get-Location).Path)\agents\agent-$i"
  if ((Test-Path "$agent") -eq $false) {
    mkdir "$agent" | Out-Null
    write-host "Unzipping agent $i on $agent"
    [System.IO.Compression.ZipFile]::ExtractToDirectory("$agents_dir\vsts-agent.zip", "$agent")
  }
}

Remove-Item "$agents_dir\vsts-agent.zip"

Write-Host "Bootstrap done."
$Error.Clear()