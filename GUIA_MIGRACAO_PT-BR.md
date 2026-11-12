# Integração Souzaiosoficial EXTERNAL sobre 3105

Esta cópia foi preparada a partir do `3105-main.zip`; ela não altera nem publica no GitHub.

## O que foi integrado

- Fluxo atual de ativação/licença do repositório GitHub (`LicenseManager` e `LicenseActivationView`), com o app 3105 bloqueado até a licença ficar ativa.
- Ícone do app e nome exibido “Souzaiosoficial EXTERNAL”. O target do Xcode continua sendo `3105` para preservar o processo de build.
- Os cinco arquivos `.3105` originais como recursos do app; na primeira carga, o aplicativo copia os arquivos para a biblioteca de patches em Application Support, sem sobrescrever pacotes que já estejam instalados.
- Código-base, telas, serviços de pareamento, marketplace, idiomas e melhorias de compatibilidade da base 3105 foram mantidos.

## Pontos que precisam de validação no Mac/iPhone

- O ambiente usado para esta preparação não tem Xcode, então não foi possível compilar o projeto nem testar em um dispositivo. Faça primeiro um build local no Xcode para iOS e, depois, teste ativação, pareamento e importação/aplicação dos pacotes no aparelho desejado.
- O `LicenseManager` copiado do GitHub usa validação pelo serviço `https://souzakeys.duckdns.org`; não é o modo local descrito no README do ZIP original. Verifique se esse servidor é o comportamento pretendido e se continuará disponível. As chamadas atuais enviam a chave de licença e o identificador do dispositivo como parâmetros de uma requisição GET; revise o endpoint e os registros do servidor antes de distribuir.
- O workflow foi mantido no modo simples do seu repositório: compila um IPA unsigned e armazena como artefato da execução. Ele não cria releases, não assina o app e não acrescenta entitlements privados automaticamente.
- `holograma.3105` e `peito.3105` são byte-a-byte idênticos e têm o mesmo ID interno de pacote; a biblioteca 3105 agrupa itens pelo ID, então eles podem aparecer como um único pacote.
- O arquivo `migration-reference/GitHub-EXTERNAL-Dashboard.unintegrated.swift` foi preservado apenas para referência. Ele não estava incluído no target Xcode do repositório e chama símbolos auxiliares ausentes (`AnimatedHyperBackdrop`, `PatchAudioFeedback` e `PatchUnlockPrompt`), por isso não o conectei à navegação nesta primeira integração. A interface principal continua sendo a navegação nova do 3105.
- Mantive o Bundle Identifier que já estava na base (`com.apple.mobile.MobileHouseArrest`) e não alterei entitlements nem assinatura. Confirme que essa identidade é intencional antes de distribuir ou assinar a aplicação.

## Abrir e compilar

1. Descompacte o ZIP no Mac e abra `ThreeOneOSFive.xcodeproj` no Xcode.
2. Selecione o target `3105`, um destino iOS compatível e faça **Product → Build**.
3. Revise e configure assinatura, Bundle Identifier e perfil de provisionamento conforme o método legítimo de distribuição escolhido.

A integração é um ponto de partida para revisão, não uma garantia de compatibilidade em todos os dispositivos ou versões do iOS.
