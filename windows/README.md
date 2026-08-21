# Lion Pass para Windows

Aplicação nativa para Windows 10 (build 19041+) e Windows 11, construída com .NET 8 e WinUI 3.

## Recursos implementados

- criação, desbloqueio e bloqueio de cofres `.lionvault` v1/v2;
- interoperabilidade criptográfica com macOS/iOS;
- Windows Hello com a chave protegida por DPAPI para o usuário atual;
- logins, cartões, notas seguras, identidades, favoritos e categorias;
- pesquisa, filtros, ordenação, auditoria local e gerador seguro;
- copiar usuário, senha e site com limpeza automática do clipboard;
- abrir site no navegador padrão;
- edição, histórico de senhas, lixeira, restauração e exclusão permanente;
- importação e exportação do cofre, backup atômico e chave de recuperação;
- identidade visual Cyan/Azul/Roxo do Lion Pass.

## Requisitos de desenvolvimento

- Windows 10 19041 ou mais recente;
- Visual Studio 2022 com **.NET desktop development** e **Windows App SDK C# Templates**;
- .NET SDK 8.

## Executar

```powershell
dotnet restore LionPass.Windows.sln
dotnet run --project src/LionPass.App/LionPass.App.csproj -p:Platform=x64
```

## Testar

```powershell
dotnet test ..\shared\dotnet\LionPass.Core.Tests\LionPass.Core.Tests.csproj -c Release
```

## Gerar instalador `.exe`

Abra PowerShell e execute:

```powershell
.\scripts\build-installer.ps1 -Architecture x64
```

O resultado será criado em `windows/installer/output/LionPass-Windows-x64-Setup.exe`. Para uso público, assine o executável e o instalador com um certificado de assinatura de código. Sem assinatura, o Windows SmartScreen pode exibir um aviso.

## Dados locais

O cofre e o backup ficam em `%LOCALAPPDATA%\Lion Code Technology\Lion Pass`. A chave do Windows Hello é cifrada pelo DPAPI e vinculada ao usuário do Windows; ela não é portátil e nunca substitui a senha mestra ou a chave de recuperação.
