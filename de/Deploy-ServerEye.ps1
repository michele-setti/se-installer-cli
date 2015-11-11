﻿<#

.SYNOPSIS
This is the (mostly) silent Server-Eye installer.

.DESCRIPTION
This script will help to install Server-Eye on systems without a full UI or when a full interactive setup is not needed.
Right now this script can download the current version of the client, install the client, setup an OCC-Connector and setup a Sensorhub.

.PARAMETER Download
Downloads the newest .msi files for Server-Eye.

.PARAMETER Install
Installs Server-Eye using the .msi files in the current directory.

.PARAMETER Offline
Skips all online checks. Use this only if the computer does not have an Internet connection.

.EXAMPLE
./Deploy-ServerEye.ps1 -Download
This just downloads the current version of the client setup.

.EXAMPLE
./Deploy-ServerEye.ps1 -Download -Install
This will download the current version of ServerEye and install it on this computer.

.EXAMPLE
./Deploy-ServerEye.ps1 -Download -Install -Deploy All -Customer XXXXXX -Secret YYYYYY
This will download the current version of ServerEye and install it on this computer.
This will also set up an OCC-Connector and a Sensorhub on this computer for the given customer.
The parameters Customer and Secret are required for this.

.EXAMPLE
./Deploy-ServerEye.ps1 -Download -Install -Deploy SenorhubOnly -Customer XXXXXX -Secret YYYYYY -ParentGuid ZZZZZZ
This will download the current version of ServerEye and install it on this computer.
This will also set up a Sensorhub on this computer for the given customer.
The parameters Customer, Secret and ParentGuid are required for this.

.NOTES
Creating customers with this is not yet supported.

.LINK

https://github.com/Server-Eye/se-installer-cli

#>

[CmdletBinding(DefaultParametersetName='None')]

param(
    [switch] $Install,
    [switch] $Download,
    [switch] $Offline, 
    [Parameter(ParameterSetName='DeployData', Mandatory=$true)] [ValidateSet("All", "SensorHubOnly")] [string] $Deploy,
    [Parameter(ParameterSetName='DeployData', Mandatory=$true)] [string] $Customer,
    [Parameter(ParameterSetName='DeployData', Mandatory=$true)] [string] $Secret,
    [Parameter(ParameterSetName='DeployData', Mandatory=$false)] [string] $NodeName,
    [Parameter(ParameterSetName='DeployData', Mandatory=$false)] [string] $ParentGuid,
    [Parameter(ParameterSetName='DeployData', Mandatory=$false)] [string] $HubPort ="11010",
    [Parameter(ParameterSetName='DeployData', Mandatory=$false)] [string] $ConnectorPort="11002"
)

$version = 380
$occServer = "occ.server-eye.de"
$apiServer = "api.server-eye.de"
$configServer = "config.server-eye.de"
$pushServer = "push.server-eye.de"
$queueServer = "queue.server-eye.de"
$baseDownloadUrl = "https://$occServer/download"
$cloudIdentifier = "se"
$vendor = "Vendor.ServerEye"

function is64bit() {
  return ([IntPtr]::Size -eq 8)
}

function get-programfilesdir() {
  if (is64bit -eq $true) {
    (Get-Item "Env:ProgramFiles(x86)").Value
  }
  else {
    (Get-Item "Env:ProgramFiles").Value
  }
}

function printHeader() {
    Write-Host "  ___                          ___         " -ForegroundColor DarkYellow
    Write-Host " / __| ___ _ ___ _____ _ _ ___| __|  _ ___ " -ForegroundColor DarkYellow
    Write-Host " \__ \/ -_) '_\ V / -_) '_|___| _| || / -_)" -ForegroundColor DarkYellow
    Write-Host " |___/\___|_|  \_/\___|_|     |___\_, \___|" -ForegroundColor DarkYellow
    Write-Host "                                  |__/     " -ForegroundColor DarkYellow
    Write-Host "                            Version 3.5.380`n" -ForegroundColor DarkGray
    Write-Host "Welcome to the (mostly) silent Server-Eye installer`n"
}

function printHelp() {
    #$me = $MyInvocation.ScriptName
    $me = ".\Deploy-ServerEye.ps1"
    printHeader

    write-host "This script needs at least one of the following parameters.`n" -ForegroundColor red

    Write-Host "$me -Download"
    Write-Host "Downloads the current version of Server-Eye.`n"

    Write-Host "$me -Install"
    Write-Host "Installs Server-Eye on this computer using the .msi files in this folder.`n"

    Write-Host "$me -Deploy [All|SensorHubOnly] -Customer XXXX -Secret YYYY"
    Write-Host "Sets up Server-Eye on this computer using the given customer and secret key.`n"

    Write-Host "$me -Download -Install -Deploy [All|SensorHubOnly] -Customer XXXX -Secret YYYY"
    Write-Host "Does all of the above.`n"


}

function main() {
    printHeader

    #Really install OCC Connector?
    if ($Deploy -eq "All") {
        $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes, this will be the only OCC-Connector.","This will continue to set up the OCC-Connector."
        $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No, another OCC-Connector is already running.  ","This will cancel everything and end this installer."
        $unkown = New-Object System.Management.Automation.Host.ChoiceDescription "I &don't know. ","Pick this if you are unsure."
        $choices = [System.Management.Automation.Host.ChoiceDescription[]]($yes,$no, $unkown)
        $caption = ""
        $message = "Only one OCC-Connector should be installed in a network.`nIs this the only OCC-Connector?"
        $result = $Host.UI.PromptForChoice($caption,$message,$choices,2)

        switch ($result) {
            0 { Write-Host "Great, let's continue."}
            1 { 
                Write-Host "Then we better stop here. Use the switch '-Deploy SensorhubOnly' instead."
                exit 1
              }
            2 { 
                Write-Host "Then we better stop here. Please make sure this is the only OCC-Connector."
                exit 1
              }
        }
    }


    Write-Output "Working "

    if ($download) {
        doDownload
    }

    if ($install) {
        install
    }

    if ($Deploy -eq "All") {
        createOccConnectorConfig
        sleep 5
        createSensorHubConfig
    }

    if ($Deploy -eq "SensorhubOnly") {
        createSensorHubConfig
    }

    Write-Host "Finished!" -ForegroundColor Green

    Write-Host "`nPlease visit https://$occServer to add Sensors`nHave fun!"
}

function doDownload() {
    Write-Host "  downloading ServerEye.Vendor... " -NoNewline
    DownloadFile "$baseDownloadUrl/vendor/$vendor/Vendor.msi" "$wd\Vendor.msi"
    Write-Host "done" -ForegroundColor Green

    Write-Host "  downloading ServerEye.Core... " -NoNewline
    DownloadFile "$baseDownloadUrl/$version/ServerEye.msi" "$wd\ServerEye.msi"
    Write-Host "done" -ForegroundColor Green

}

function install() {
    Write-Host "  installing ServerEye.Vendor...  " -NoNewline
    if (-not (Test-Path "$wd\Vendor.msi")) {
        Write-Host "failed" -ForegroundColor Red
        Write-Host "  The file Vendor.msi is missing." -ForegroundColor Red
        exit 1
    }

    Start-Process "$wd\Vendor.msi" /passive -Wait
    Write-Host "done" -ForegroundColor Green

    Write-Host "  installing ServerEye.Core...  " -NoNewline
        if (-not (Test-Path "$wd\ServerEye.msi")) {
        Write-Host "failed" -ForegroundColor Red
        Write-Host "  The file ServerEye.msi is missing." -ForegroundColor Red
        exit 1
    }

    Start-Process "$wd\ServerEye.msi" /passive -Wait
    Write-Host "done" -ForegroundColor Green
}

function createOccConnectorConfig() {
    Write-Host "  creating OCC-Connector configuration... " -NoNewline

    "customer=$Customer" | Set-Content $confFileMAC
    "secretKey=$Secret" | Add-Content $confFileMAC
    "name=$NodeName" | Add-Content $confFileMAC
    "description=" | Add-Content $confFileMAC
    "port=$ConnectorPort" | Add-Content $confFileMAC

    "servletUrl=https://$configServer/" | Add-Content $confFileMAC
    "statUrl=https://$pushServer/0.1/" | Add-Content $confFileMAC
    "pushUrl=https://$pushServer/" | Add-Content $confFileMAC
    "queueUrl=https://$queueServer/" | Add-Content $confFileMAC

    "proxyType=EdS2vHJFGTNVHy4Uq570OQ==|===" | Add-Content $confFileMAC
    "proxyUrl=L8aGFOF4VKZiWLRQEb72lA==|===" | Add-Content $confFileMAC
    "proxyPort=lo/VY9yIpiJ46BYKnAtljQ==|===" | Add-Content $confFileMAC
    "proxyDomain=lo/VY9yIpiJ46BYKnAtljQ==|===" | Add-Content $confFileMAC
    "proxyUser=lo/VY9yIpiJ46BYKnAtljQ==|===" | Add-Content $confFileMAC
    "proxyPass=lo/VY9yIpiJ46BYKnAtljQ==|===" | Add-Content $confFileMAC

    Write-Host "done" -ForegroundColor Green

    Write-Host "  starting OCC-Connector... " -NoNewline

    Set-Service MACService -StartupType Automatic
    Start-Service MACService

    Write-Host "done" -ForegroundColor Green

    Write-Host "  waiting for OCC-Connector to register with Server-Eye... " -NoNewline

    $guid = ""
    $maxWait = 300
    $wait = 0
    while ($guid -eq "" -and $wait -lt $maxWait ) {
        $x = Get-Content $confFileMAC | Select-String "guid"
        #$x = $x.Trim();
        if ($x.Line.Length -gt 1) {
            $splitX = $x.Line.ToString().Split("=")
            $guid = $splitX[1]
        }
        sleep 1
        $wait = $wait + 1
    }

    if ($guid -eq "") {
        Write-Host "failed" -ForegroundColor Red
        Write-Host "GUID was not generated in time." -ForegroundColor Red
        exit 2
    }
    $ParentGuid = $guid
    Write-Host "done" -ForegroundColor Green
}

function createSensorHubConfig() {
    Write-Host "  creating Sensorhub configuration... " -NoNewline

    "customer=$Customer" | Set-Content $confFileCC
    "secretKey=$Secret" | Add-Content $confFileCC
    "name=$NodeName" | Add-Content $confFileCC
    "description=" | Add-Content $confFileCC
    "port=$HubPort" | Add-Content $confFileCC
    if($ParentGuid -ne "") {
        "parentGuid=$ParentGuid" | Add-Content $confFileCC
    }

    Write-Host "done" -ForegroundColor Green

    Write-Host "  starting Sensorhub... " -NoNewline

    Set-Service CCService -StartupType Automatic
    Start-Service CCService

    Start-Service SE3Recovery

    Write-Host "done" -ForegroundColor Green
}

function DownloadFile($url, $targetFile) {

   $uri = New-Object "System.Uri" "$url"
   $request = [System.Net.HttpWebRequest]::Create($uri)
   $request.set_Timeout(15000) #15 second timeout
   $response = $request.GetResponse()
   $totalLength = [System.Math]::Floor($response.get_ContentLength()/1024)
   $responseStream = $response.GetResponseStream()
   $targetStream = New-Object -TypeName System.IO.FileStream -ArgumentList $targetFile, Create
   $buffer = new-object byte[] 10KB
   $count = $responseStream.Read($buffer,0,$buffer.length)
   $downloadedBytes = $count

   while ($count -gt 0) {
       $targetStream.Write($buffer, 0, $count)
       $count = $responseStream.Read($buffer,0,$buffer.length)
       $downloadedBytes = $downloadedBytes + $count
       Write-Progress -activity "Downloading file '$($url.split('/') | Select -Last 1)'" -status "Downloaded ($([System.Math]::Floor($downloadedBytes/1024))K of $($totalLength)K): " -PercentComplete ((([System.Math]::Floor($downloadedBytes/1024)) / $totalLength)  * 100)
   }

   Write-Progress -activity "Finished downloading file '$($url.split('/') | Select -Last 1)'" -Status "Done" -Completed

   $targetStream.Flush()
   $targetStream.Close()
   $targetStream.Dispose()
   $responseStream.Dispose()
}

function checkForUpdate() {
    $r = [System.Net.WebRequest]::Create("$baseDownloadUrl/$cloudIdentifier/currentVersionCli")
    $resp = $r.GetResponse()
    $reqstream = $resp.GetResponseStream()
    $sr = new-object System.IO.StreamReader $reqstream
    $result = $sr.ReadToEnd()
    if ($version -lt $result) {
        Write-Host "This version of the Server-Eye deployment script is no longer supported."
        Write-Host "Please update to the newest version with this command:"
        Write-Host "Invoke-WebRequest ""$baseDownloadUrl/$cloudIdentifier/Deploy-ServerEye.ps1"" -OutFile Deploy-ServerEye.ps1"
        exit 1
    }
}

If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
    [Security.Principal.WindowsBuiltInRole] "Administrator"))
{
    Write-Warning "You do not have Administrator rights to run this script!`nPlease re-run this script as an Administrator!`n"
    exit 1
}

If ([environment]::OSVersion.Version.Major -lt 6) {
    Write-Host ""
    Write-Host "Your operating system is not officially supported.`nThe install will most likely work but we can no longer provide support for Server-Eye on this system." 

    $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes, continue without support","The install will continue, but we cannot help you if something doesn't work."
    $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No, cancel the install","End the install right now."
    $choices = [System.Management.Automation.Host.ChoiceDescription[]]($yes,$no)
    $caption = ""
    $message = "Do you still want to install Server-Eye on this computer?"
    $result = $Host.UI.PromptForChoice($caption,$message,$choices,1)
    if($result -eq 1) { exit 1 }
}

if ($Offline.IsPresent -eq $false) { 
    checkForUpdate
}

if ($Offline -and $Download) {
    Write-Warning "Cannot use offline mode and download at the same time."
    exit 1
}


$progdir =  get-programfilesdir
$confDir = "$progdir\Server-Eye\config"
$confFileMAC = "$confDir\se3_mac.conf"
$confFileCC = "$confDir\se3_cc.conf"

if($Deploy -ne "" -and (Test-Path "$confFileMAC") -or (Test-Path "$confFileCC")) {
    Write-Host "Server-Eye is already installed on this system." -ForegroundColor Red
    Write-Host "This script works only on system without a previous Server-Eye installation" -ForegroundColor Red
    exit 1
}


$wd = split-path $MyInvocation.MyCommand.Path

if ($Install.IsPresent -eq $false -and $Download.IsPresent -eq $false -and ( $Deploy -eq "" -or $Deploy -eq $null)) {

    printHelp

    exit 0
}

main