<#
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.
#>

function Write-Log {
  param (
    [string] $message,
    [string] $severity = 'INFO',
    [string] $source = 'BootStrap',
    [string] $logName = 'Application'
  )
  if (!([Diagnostics.EventLog]::Exists($logName)) -or !([Diagnostics.EventLog]::SourceExists($source))) {
    New-EventLog -LogName $logName -Source $source
  }
  switch ($severity) {
    'DEBUG' {
      $entryType = 'SuccessAudit'
      $eventId = 2
      break
    }
    'WARN' {
      $entryType = 'Warning'
      $eventId = 3
      break
    }
    'ERROR' {
      $entryType = 'Error'
      $eventId = 4
      break
    }
    default {
      $entryType = 'Information'
      $eventId = 1
      break
    }
  }
  Write-EventLog -LogName $logName -Source $source -EntryType $entryType -Category 0 -EventID $eventId -Message $message
  if ([Environment]::UserInteractive) {
    $fc = @{ 'Information' = 'White'; 'Error' = 'Red'; 'Warning' = 'DarkYellow'; 'SuccessAudit' = 'DarkGray' }[$entryType]
    Write-Host  -object $message -ForegroundColor $fc
  }
}
function Setup-Logging {
  param (
    [string] $ext_src = "https://s3-us-west-2.amazonaws.com/ronin-puppet-package-repo/Windows/prerequisites",
    [string] $local_dir = "$env:systemdrive\BootStrap",
    [string] $nxlog_msi = "nxlog-ce-2.10.2150.msi",
    [string] $nxlog_conf = "nxlog.conf",
    [string] $nxlog_pem  = "papertrail-bundle.pem",
    [string] $nxlog_dir   = "$env:systemdrive\Program Files (x86)\nxlog"

  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    New-Item -ItemType Directory -Force -Path $local_dir

    Invoke-WebRequest  $ext_src/$nxlog_msi -outfile $local_dir\$nxlog_msi -UseBasicParsing
    msiexec /i $local_dir\$nxlog_msi /passive
    while (!(Test-Path "$nxlog_dir\conf\")) { Start-Sleep 10 }
    Invoke-WebRequest  $ext_src/$nxlog_conf -outfile "$nxlog_dir\conf\$nxlog_conf" -UseBasicParsing
    while (!(Test-Path "$nxlog_dir\conf\")) { Start-Sleep 10 }
    Invoke-WebRequest  $ext_src/$nxlog_pem -outfile "$nxlog_dir\cert\$nxlog_pem" -UseBasicParsing
    Restart-Service -Name nxlog -force
  }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}
function InstallRoninModule {
  param (
    [string] $src_Organisation,
    [string] $src_Repository,
    [string] $src_Revision,
    [string] $moduleName,
    [string] $local_dir = "$env:systemdrive\BootStrap",
    [string] $filename = ('{0}.psm1' -f $moduleName),
    [string] $module_name = ($moduleName).replace(".pms1",""),
    [string] $modulesPath = ('{0}\Modules\{1}' -f $pshome, $moduleName),
    [string] $bootstrap_module = "$modulesPath\bootstrap",
    [string] $moduleUrl = ('https://raw.githubusercontent.com/{0}/{1}/{2}/provisioners/windows/modules/{3}' -f $src_Organisation, $src_Repository, $src_Revision, $filename)
  )
  begin {
    Write-Log -message ('{0} :: begin - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
  process {
    mkdir $bootstrap_module  -ErrorAction SilentlyContinue
    Invoke-WebRequest $moduleUrl -OutFile "$bootstrap_module\\$filename" -UseBasicParsing
    Get-Content -Encoding UTF8 "$bootstrap_module\\$filename" | Out-File -Encoding Unicode "$modulesPath\\$filename"
    Import-Module -Name $moduleName
    }
  end {
    Write-Log -message ('{0} :: end - {1:o}' -f $($MyInvocation.MyCommand.Name), (Get-Date).ToUniversalTime()) -severity 'DEBUG'
  }
}

# Ensuring scripts can run uninhibited
# This is noisey but works
Set-ExecutionPolicy unrestricted -force  -ErrorAction SilentlyContinue

$workerType = ((((Invoke-WebRequest -Headers @{'Metadata'=$true} -UseBasicParsing -Uri ('http://169.254.169.254/metadata/instance?api-version=2019-06-04')).Content) | ConvertFrom-Json).compute.tagsList| ? { $_.name -eq ('workerType') })[0].value
$src_Organisation = ((((Invoke-WebRequest -Headers @{'Metadata'=$true} -UseBasicParsing -Uri ('http://169.254.169.254/metadata/instance?api-version=2019-06-04')).Content) | ConvertFrom-Json).compute.tagsList| ? { $_.name -eq ('sourceOrganisation') })[0].value
$src_Repository = ((((Invoke-WebRequest -Headers @{'Metadata'=$true} -UseBasicParsing -Uri ('http://169.254.169.254/metadata/instance?api-version=2019-06-04')).Content) | ConvertFrom-Json).compute.tagsList| ? { $_.name -eq ('sourceRepository') })[0].value
$src_Revision = ((((Invoke-WebRequest -Headers @{'Metadata'=$true} -UseBasicParsing -Uri ('http://169.254.169.254/metadata/instance?api-version=2019-06-04')).Content) | ConvertFrom-Json).compute.tagsList| ? { $_.name -eq ('sourceRevision') })[0].value
$image_provisioner = 'azure'

If(test-path 'HKLM:\SOFTWARE\Mozilla\ronin_puppet') {
    $stage =  (Get-ItemProperty -path "HKLM:\SOFTWARE\Mozilla\ronin_puppet").bootstrap_stage
}
If(!(test-path 'HKLM:\SOFTWARE\Mozilla\ronin_puppet')) {
    Setup-Logging
    InstallRoninModule -moduleName common-bootstrap -src_Organisation $src_Organisation -src_Repository $src_Repository -src_Revision $src_Revision
    InstallRoninModule -moduleName azure-bootstrap -src_Organisation $src_Organisation -src_Repository $src_Repository -src_Revision $src_Revision
    Set-RoninRegOptions  -workerType $workerType -src_Organisation $src_Organisation -src_Repository $src_Repository -src_Revision $src_Revision -image_provisioner $image_provisioner
    AzInstall-Prerequ
    AzMount-DiskTwo
    AzSet-DriveLetters
    exit 0
}
If (($stage -eq 'setup') -or ($stage -eq 'inprogress')){
    InstallRoninModule -moduleName common-bootstrap -src_Organisation $src_Organisation -src_Repository $src_Repository -src_Revision $src_Revision
    InstallRoninModule -moduleName azure-bootstrap -src_Organisation $src_Organisation -src_Repository $src_Repository -src_Revision $src_Revision
    Ronin-PreRun
    AzBootstrap-Puppet
    exit 0
}
If ($stage -eq 'complete') {
    InstallRoninModule -moduleName common-bootstrap -src_Organisation $src_Organisation -src_Repository $src_Repository -src_Revision $src_Revision
    InstallRoninModule -moduleName azure-bootstrap -src_Organisation $src_Organisation -src_Repository $src_Repository -src_Revision $src_Revision
    Bootstrap-CleanUp
    exit 0
}
