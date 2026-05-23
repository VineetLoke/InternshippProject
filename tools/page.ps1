<#
.SYNOPSIS
Pages long terminal output so you can scroll with the keyboard.

.EXAMPLES
.\tools\page.ps1 git log --oneline --all
.\tools\page.ps1 Get-Content README.md
Get-Content README.md | .\tools\page.ps1

Keyboard:
- Space: next page
- Enter: next line
- q: quit
#>

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Command
)

if ($Command.Count -gt 0) {
    $exe = $Command[0]
    $args = if ($Command.Count -gt 1) { $Command[1..($Command.Count - 1)] } else { @() }
    & $exe @args 2>&1 | Out-Host -Paging
    exit $LASTEXITCODE
}

$input | Out-Host -Paging
