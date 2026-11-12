# Projeto Souzaiosoficial EXTERNAL sobre 3105

## Estrutura desta integração

O `ContentView` do `original.zip` — o layout escuro com as abas Principal, Visual e Perfil — agora é a interface raiz do aplicativo. O `ContentView` da base 3105 não fica mais como tela inicial; sua navegação e suas ferramentas foram preservadas como uma tela secundária aberta pelo botão **FERRAMENTAS 3105** dentro de Perfil.

A aba customizada de baixo ganhou **Emparelhar**, que abre o `PairingVPNView` do 3105. Assim, a navegação principal mantém o desenho original e o fluxo de Emparelhamento continua disponível sem usar a barra de abas padrão do 3105. A tela de ferramentas 3105 ainda oferece Home, Novidades, Fontes, Instalados, Arquivos (conforme modo de desenvolvedor) e Busca.

O painel original foi adaptado para compartilhar o `PatchProjectStore` e o `LicenseManager` globais do 3105, em vez de criar uma segunda store. Também contém a resolução por alias para `peito.3105`/`holograma.3105`, que são pacotes idênticos com o mesmo ID interno. Os componentes visuais ausentes no projeto original foram incluídos em `SouzaiosoficialDashboardSupport.swift`.

## Licença e distribuição

A tela de ativação continua sendo apresentada pelo fluxo do `LicenseManager` quando não há licença ativa. Se uma licença já foi validada, a atualização pode reutilizar o estado guardado no Keychain e não pedir a chave novamente. O aviso visual **ACESSO LIBERADO** segue dentro da interface original.

O `LicenseManager` usa o endpoint `https://souzakeys.duckdns.org`; as requisições GET enviam a chave e o identificador do dispositivo. Confirme que esse endpoint é seu e que aceita esse comportamento antes de distribuir o aplicativo.

O Bundle Identifier mantido é `com.apple.mobile.MobileHouseArrest`, como na base. Revise-o e configure assinatura/provisionamento antes de distribuição. O workflow atual gera uma IPA unsigned; ele não publica Releases nem assina o aplicativo automaticamente.

## Validação

Os arquivos foram verificados estaticamente e a referência antiga à aba duplicada foi removida. Esta preparação não tem Xcode, portanto não confirma uma compilação iOS nem comportamento no aparelho. Compile no Xcode ou execute o workflow GitHub Actions e teste Principal, Visual, Perfil, Pairing, aplicação/restauração dos patches e Ferramentas 3105 no dispositivo.
