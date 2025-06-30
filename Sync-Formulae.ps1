<#
.SYNOPSIS
    Synchronizes the formulae in the local repository with the formulae in the
    Homebrew repository.
.DESCRIPTION
    Given a manifest of Homebrew formulae, pulls the original Homebrew version
    of each formula and updates the formula based on a set of rules.

    "WhatIf" will allow you to do a dry-run that will show you what formulae
    would be updated in a real run. It will still go get the original formulae
    from Homebrew, but it will not update the local formulae.

    The value returned from the script is the array of updated formulae.
.PARAMETER Manifest
    The location of the JSON manifest of formulae to synchronize.
.EXAMPLE
    ./Sync-Formulae.ps1

    Execute synchronization.
.EXAMPLE
    ./Sync-Formulae.ps1 -Manifest ./manifest.json -Verbose -WhatIf

    Execute a dry run of synchronization with debug output.
#>
[CmdletBinding(SupportsShouldProcess = $True)]
[OutputType([string[]])]
Param(
    [Parameter(Mandatory = $False)]
    [ValidateNotNullOrEmpty()]
    [string]
    $Manifest = './manifest.json'
)

Begin {
    Function Convert-ToSafeFormula {
        [CmdletBinding()]
        Param(
            [Parameter(Mandatory = $True, ValueFromPipeline = $True)]
            [ValidateNotNullOrEmpty()]
            [string]
            $Content
        )

        Process {
            # Replace URLs.
            $Content = $Content -replace 'https://ftp.gnu.org/gnu/', 'https://ftpmirror.gnu.org/'
            $Content = $Content -replace 'https://downloads.sourceforge.net/project/swig/swig/', 'https://github.com/tillig/homebrew-mods/releases/download/'
            $Content
        }
    }

    Function Import-RemoteFormula {
        [CmdletBinding()]
        Param(
            [Parameter(Mandatory = $True)]
            [ValidateNotNullOrEmpty()]
            [string]
            $Formula
        )

        $remoteUrl = "https://raw.githubusercontent.com/Homebrew/homebrew-core/refs/heads/master/Formula/$Formula"
        Write-Verbose "Remote location for $Formula is $remoteUrl."
        $tempFile = New-TemporaryFile -WhatIf:$False
        Invoke-WebRequest -Uri $remoteUrl -OutFile $tempFile
        $tempFile
    }
}

Process {
    If (-not (Test-Path $Manifest)) {
        Write-Error 'The manifest file does not exist.'
        Exit 1
    }

    $baseFormulaPath = [System.IO.Path]::GetFullPath("$PSScriptRoot/Formula")
    New-Item -ItemType Directory -Path $baseFormulaPath -Force -WhatIf:$False | Out-Null

    $formulae = [string[]](Get-Content $Manifest | ConvertFrom-Json -Depth 10)
    $formulae | ForEach-Object {
        $formula = $_
        $returnItem = $null
        $originalFile = Import-RemoteFormula -Formula $formula
        Try {
            $content = Get-Content $originalFile -Raw
            $content = $content | Convert-ToSafeFormula
            $content | Set-Content -Path $originalFile -Force -WhatIf:$False

            $destinationFile = "$baseFormulaPath/$formula"
            $destinationFolder = [System.IO.Path]::GetDirectoryName($destinationFile)
            If (-not (Test-Path $destinationFolder)) {
                New-Item -ItemType Directory -Path $destinationFolder -Force | Out-Null
            }

            If (Test-Path $destinationFile) {
                $comparison = Compare-Object (Get-Content $originalFile) (Get-Content $destinationFile)
                If ($comparison -and $PSCmdlet.ShouldProcess($formula, 'Update Formula')) {
                    Write-Verbose "Updating $formula."
                    Copy-Item $originalFile $destinationFile -Force
                    $returnItem = $destinationFile
                }
            }
            Else {
                If ($PSCmdlet.ShouldProcess($formula, 'Create Formula')) {
                    Write-Verbose "Creating $formula."
                    Copy-Item $originalFile $destinationFile
                    $returnItem = $destinationFile
                }
            }
        }
        Finally {
            Remove-Item $originalFile -Force -ErrorAction SilentlyContinue -WhatIf:$False | Out-Null
            If ($returnItem) {
                $returnItem
            }
        }
    }
}
