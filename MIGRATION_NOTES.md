# Migração — Souzaiosoficial EXTERNAL

## O que foi preservado do `original.zip`

- Tela principal original, abas, textos, cores, banner e identidade visual vermelha/preta.
- Tela de ativação por key e integração existente com o serviço de validação (`/validar` e `/checar`).
- Estados e ações dos botões de patch, mensagens de status, restauração e feedback sonoro.
- Ícone original e os cinco recursos `.3105` incluídos no pacote antigo.

## O que foi mantido do `projeto novo.zip`

- Projeto Xcode, componentes de sistema, serviços e estrutura que compõem a base de compatibilidade mais recente.
- Política de suporte declarada pela própria base: iOS 26.0–26.7.2 e iOS 27.0–27.2. Não foi ampliada para versões posteriores sem evidência no código.
- APIs atuais de armazenamento/carregamento dos pacotes. A biblioteca foi adaptada para importar os recursos `.3105` embarcados no primeiro carregamento.
- Identificador de bundle e configurações de instalação da base nova foram mantidos.

## Ajustes da integração

- A tela principal passou a observar o `PatchProjectStore` compartilhado da base nova, em vez de criar uma instância separada.
- O estado dos botões é sincronizado novamente depois que o carregamento assíncrono dos pacotes termina.
- A tela de ativação e o gerenciador de licença do original foram adicionados ao alvo do Xcode.
- Foi criado um esquema compartilhado `3105` para o build automatizado não depender de configuração local do Xcode.

## Verificações feitas neste ambiente

- `Info.plist` validado.
- `project.pbxproj` validado.
- Sintaxe dos 56 arquivos Swift verificada com `swiftc -frontend -parse`.
- XML do esquema compartilhado validado.

**Limitação:** este ambiente não tem Xcode/macOS, então não foi possível executar `xcodebuild`, testar o app em um iPhone ou gerar/assinar um IPA aqui. A verificação de sintaxe não equivale a uma compilação completa.

## Gerar o IPA no GitHub

O workflow em `.github/workflows/build-unsigned-ipa.yml` executa em `macos-latest`, compila o scheme `3105` sem assinatura e publica o artefato `Souzaiosoficial-EXTERNAL-unsigned-ipa`. Ao integrar esta alteração à branch `main`, o workflow será disparado automaticamente; também existe a opção manual (`workflow_dispatch`).

O IPA gerado é **unsigned**. Para instalar pelo ESign/GBox, importe-o no instalador e faça a assinatura com um certificado/perfil válido.
