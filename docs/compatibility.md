# Compatibilidade Apple ↔ Windows ↔ Linux

Uma alteração no modelo ou na criptografia só pode ser publicada quando os testes comprovarem:

1. abertura no Windows e Linux de um cofre sintético criado no Apple;
2. abertura no Apple e Linux de um cofre sintético criado no Windows;
3. abertura no Apple e Windows de um cofre sintético criado no Linux;
4. preservação de IDs, datas, categorias, histórico, campos personalizados e lixeira;
5. rejeição de senha errada, arquivo truncado, tag alterada e parâmetros KDF abusivos.

Windows e Linux usam diretamente `shared/dotnet/LionPass.Core`. A interface e o armazenamento protegido da chave são específicos da plataforma, mas o envelope, a serialização e as regras do cofre são os mesmos.

Fixtures nunca podem conter credenciais reais. O arquivo `.gitignore` bloqueia cofres fora de `shared/test-vaults/fixtures/`.
