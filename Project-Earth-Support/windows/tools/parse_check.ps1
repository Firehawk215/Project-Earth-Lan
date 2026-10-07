param([string]$Path)
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
foreach ($e in $errors) { "Zeile {0}, Spalte {1}: {2}" -f $e.Extent.StartLineNumber, $e.Extent.StartColumnNumber, $e.Message }
"Parser: {0} Fehler, {1} Funktionen" -f $errors.Count, @($ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)).Count
# PS-7-Syntax, die der Parser von PowerShell 7 durchlaesst, Windows PowerShell 5.1 aber nicht kennt
$bad = @($ast.FindAll({ $a = $args[0]; ($a.GetType().Name -in 'TernaryExpressionAst', 'PipelineChainAst') }, $true))
foreach ($b in $bad) { "PS7-Syntax in Zeile {0}: {1}" -f $b.Extent.StartLineNumber, $b.GetType().Name }
foreach ($t in $tokens) { if ($t.Kind -in 'QuestionQuestion', 'QuestionQuestionEquals', 'QuestionDot', 'QuestionLBracket', 'AndAnd', 'OrOr') { "PS7-Operator in Zeile {0}: {1}" -f $t.Extent.StartLineNumber, $t.Text } }
# Aufrufe unbekannter eigener Funktionen (Tippfehler) finden
$defined = @{}; foreach ($f in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) { $defined[$f.Name] = 1 }
$calls = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)
$unknown = @{}
foreach ($c in $calls) { $n = $c.GetCommandName(); if ($n -and $n -match '-Pes|^T$|^Show-Pes|^New-Pes' -and -not $defined.ContainsKey($n)) { $unknown[$n] = $c.Extent.StartLineNumber } }
foreach ($k in $unknown.Keys) { "Unbekannte Funktion {0} (Zeile {1})" -f $k, $unknown[$k] }
if ($errors.Count -gt 0 -or $bad.Count -gt 0 -or $unknown.Count -gt 0) { exit 1 }
