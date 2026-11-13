# Souzaiosoficial EXTERNAL — base 3105 v2.2

Projeto reconstruído usando duas fontes:

- `original.zip`: interface, identidade visual, tela de ativação por KEY e pacotes `.3105` originais.
- `3105-main.zip`: estrutura atualizada, fluxo de LocalDevVPN/Device Pairing, resolução de acesso ao contêiner e componentes da versão 2.2.

## Build

O workflow `.github/workflows/build-unsigned-ipa.yml` compila o target `3105` em um runner macOS e publica um IPA **sem assinatura** nos artefatos do GitHub Actions.

## Compatibilidade e acesso ao aplicativo de destino

A política incluída na base 3105 v2.2 declara rotas de suporte que abrangem iOS 27.0–27.2+ e oferece a tela LocalDevVPN/Device Pairing. Isso é uma declaração do código-base, não uma confirmação de funcionamento no seu aparelho.

Compilar ou instalar o IPA não garante, por si só, que o contêiner de outro aplicativo será localizado. Para operações que dependem desse acesso, o pareamento e o acesso real ao contêiner precisam estar configurados e disponíveis. A mensagem de contêiner indisponível não prova, sozinha, que a versão do iOS é incompatível.

O workflow deste projeto gera um IPA sem assinatura e não injeta entitlements privados nem remove o sandbox. Instalar pelo ESign/GBox, por si só, não concede acesso privado aos contêineres de outros aplicativos.

## O que foi integrado

- Interface principal, abas, textos, cores, banner e fluxo de licença do `original.zip`.
- Ativação e validação da KEY pelo `LicenseManager` original.
- Ícone original e cinco pacotes `.3105` incluídos como recursos do aplicativo.
- Instalação automática dos pacotes incluídos e desbloqueio pela senha interna usada no projeto original.
- Tela LocalDevVPN/Device Pairing da base 2.2 acessível pela aba Perfil.
- Componentes da base 2.2 responsáveis pela política de suporte e resolução de acesso mantidos sem substituição pelo código antigo.
- Workflow para gerar IPA de teste sem criar releases automaticamente.

## Validação pendente

A estrutura do projeto, os arquivos plist, as referências de recursos e a sintaxe dos arquivos Swift foram verificados. Este ambiente não possui Xcode, então não foi possível executar a compilação real nem testar no iOS 27.2. Isso precisa ser validado pelo GitHub Actions e no iPhone.
