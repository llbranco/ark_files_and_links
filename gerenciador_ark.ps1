# ==========================================
# script para permitir a troca entre versões do ark
# de forma semi-transparente
# ==========================================
# creditos: LLBRANCO

#
# caso vc tenha erros de Script nao assinado / Execucao desabilitada
# rode o seguinte comando
#
# Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
# depois rode o script novamente
#
# instruções de uso
# baixe 1 versão do ark (aquatica ou pre-aquatica)
# crie as pastas ARK_aquatica e ARK-preaquatica
#
# com a Steam fechada
# mova o conteúdo da pasta ARK da versão instalada pra pasta referente
# encontre o arquivo appmanifest_346110.acf e mova e renomeie para
# ARK_aquatica e ARK-preaquatica como aquatica.acf ou preaquatica.acf
#
# feche o SCRIPT
# abra a steam e baixe a outra versão, repita o procedimento

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Solicitando privilegios de Administrador..."
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Exit
}

# ==========================================
# SCRIPT PRINCIPAL
# ==========================================
$steamapps = "C:\Program Files (x86)\Steam\steamapps"
$common = "$steamapps\common"
$ark = "$common\ARK"
$aquatica = "C:\ARK_aquatica"
$preaquatica = "C:\ARK_pre-aquatica"
$manifesto = "$steamapps\appmanifest_346110.acf"

Clear-Host
Write-Host "---------------------------------------------------"
Write-Host "          EXECUTANDO CHECKLIST DE SEGURANCA..."
Write-Host "---------------------------------------------------"

function Check-Steam {
    while (Get-Process -Name "steam" -ErrorAction SilentlyContinue) {
        Clear-Host
        Write-Host "[AVISO] A Steam esta aberta. Feche-a para continuar..." -ForegroundColor Yellow
        Read-Host "Pressione Enter para tentar novamente apos fechar a Steam"
    }
}

Check-Steam
Write-Host "[ OK ] Steam Fechada."

if (-not (Test-Path $aquatica)) {
    Write-Host "[ INFO ] Criando pasta da versao Aquatica em $aquatica..."
    New-Item -ItemType Directory -Path $aquatica | Out-Null
}
if (-not (Test-Path $preaquatica)) {
    Write-Host "[ INFO ] Criando pasta da versao Pre-Aquatica em $preaquatica..."
    New-Item -ItemType Directory -Path $preaquatica | Out-Null
}

$status = "Nenhum (Pronto para configuracao)"
if (Test-Path $ark) {
    $item = Get-Item $ark
    if ($item.Attributes -match "ReparsePoint") {
        $target = $item.Target
        if ($target -eq $aquatica) { $status = "Versao Aquatica" }
        if ($target -eq $preaquatica) { $status = "Versao Pre-Aquatica" }
    } else {
        Write-Host "[ALERTA] A pasta $ark existe mas NAO eh um link." -ForegroundColor Yellow
        Write-Host "Se vc ja moveu os arquivos, delete a pasta vazia em $ark"
        $status = "Pasta Fisica Detectada (Inseguro)"
        Read-Host "Pressione Enter para continuar"
    }
} else {
    Write-Host "[ INFO ] Criando link simbolico inicial padrao..."
    New-Item -ItemType SymbolicLink -Path $ark -Value $aquatica | Out-Null
    $status = "Versao Aquatica (Link Inicial Criado)"
}

Write-Host "[ OK ] Checklist Concluido com Sucesso!"
Start-Sleep -Seconds 2

while ($true) {
    Check-Steam
    if (Test-Path $ark) {
        $item = Get-Item $ark
        if ($item.Attributes -match "ReparsePoint") {
            $target = $item.Target
            if ($target -eq $aquatica) { $status = "Versao Aquatica" }
            if ($target -eq $preaquatica) { $status = "Versao Pre-Aquatica" }
        }
    }

    Clear-Host
    Write-Host "---------------------------------------------------"
    Write-Host "               GERENCIADOR DO ARK"
    Write-Host "---------------------------------------------------"
    Write-Host "Caminho Aquatica:     $aquatica"
    Write-Host "Caminho Pre-Aquatica: $preaquatica"
    Write-Host "---------------------------------------------------"
    Write-Host "Status Atual:         [$status]"
    Write-Host "---------------------------------------------------"
    Write-Host "Escolha uma opcao:"
    Write-Host "[1] Ativar Versao Aquatica"
    Write-Host "[2] Ativar Versao Pre-Aquatica"
    Write-Host "[3] Forcar Fechamento da Steam"
    Write-Host "[4] Sair"
    Write-Host "---------------------------------------------------"
    $opcao = Read-Host "Digite a opcao (1, 2, 3 ou 4)"

    if ($opcao -eq "1") {
        Write-Host ""
        Write-Host "Modificando ambiente para Aquatica..."
        if (Test-Path $ark) {
            $item = Get-Item $ark
            if ($item.Attributes -match "ReparsePoint") { $item.Delete() } else { Remove-Item $ark -Force -Recurse -ErrorAction SilentlyContinue }
        }
        New-Item -ItemType SymbolicLink -Path $ark -Value $aquatica | Out-Null
        if (Test-Path $manifesto) { Remove-Item $manifesto -Force -ErrorAction SilentlyContinue }
        
        $targetManifest = "$aquatica\aquatica.acf"
        if (Test-Path $targetManifest) {
            Copy-Item $targetManifest $manifesto -Force
            $status = "Versao Aquatica"
            Write-Host "Parabens Nubi Nubi, Versao Aquatica Ativada!" -ForegroundColor Green
        } else {
            Write-Host "[AVISO] aquatica.acf nao encontrado dentro de $aquatica." -ForegroundColor Yellow
            $status = "Versao Aquatica (Sem Manifesto)"
        }
        Read-Host "Pressione Enter para retornar ao menu"
    }
    elseif ($opcao -eq "2") {
        Write-Host ""
        Write-Host "Modificando ambiente para Pre-Aquatica..."
        if (Test-Path $ark) {
            $item = Get-Item $ark
            if ($item.Attributes -match "ReparsePoint") { $item.Delete() } else { Remove-Item $ark -Force -Recurse -ErrorAction SilentlyContinue }
        }
        New-Item -ItemType SymbolicLink -Path $ark -Value $preaquatica | Out-Null
        if (Test-Path $manifesto) { Remove-Item $manifesto -Force -ErrorAction SilentlyContinue }
        
        $targetManifest = "$preaquatica\preaquatica.acf"
        if (Test-Path $targetManifest) {
            Copy-Item $targetManifest $manifesto -Force
            $status = "Versao Pre-Aquatica"
            Write-Host "Parabens Nubi Nubi, Versao Pre-Aquatica Ativada!" -ForegroundColor Green
        } else {
            Write-Host "[AVISO] preaquatica.acf nao encontrado dentro de $preaquatica." -ForegroundColor Yellow
            $status = "Versao Pre-Aquatica (Sem Manifesto)"
        }
        Read-Host "Pressione Enter para retornar ao menu"
    }
    elseif ($opcao -eq "3") {
        Write-Host "Fechando processos da Steam..."
        Stop-Process -Name "steam" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
    elseif ($opcao -eq "4") {
        break
    }
}
