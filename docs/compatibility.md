# Compatibilidade Apple ↔ Windows

Uma alteração no modelo ou na criptografia só pode ser publicada quando os testes comprovarem:

1. abertura no Windows de um cofre sintético criado no Apple;
2. abertura no Apple de um cofre sintético criado no Windows;
3. preservação de IDs, datas, categorias, histórico, campos personalizados e lixeira;
4. rejeição de senha errada, arquivo truncado, tag alterada e parâmetros KDF abusivos.

Fixtures nunca podem conter credenciais reais. O arquivo `.gitignore` bloqueia cofres fora de `shared/test-vaults/fixtures/`.
