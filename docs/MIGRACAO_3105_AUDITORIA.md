# Auditoria inicial — migração Souzaiosoficial EXTERNAL para 3105-main

## Decisões confirmadas
- Base técnica: `3105-main`.
- Nome/identidade do app: `Souzaiosoficial EXTERNAL`.
- Manter ativação pela API e a tela de chave.
- Adotar a interface e os módulos novos do 3105.
- Recuperar os cinco arquivos `.3105` do projeto original.

## Resultado da comparação dos ZIPs
Os dois projetos compartilham boa parte da árvore, mas há diferenças relevantes. O 3105 inclui módulos ausentes no original:
- `helpers/LocalVPNPairingService.swift`
- `views/PairingVPNView.swift`
- `helpers/PackageRepositoryModels.swift`
- `helpers/PackageRepositoryStore.swift`
- `views/RepositoryMarketplaceView.swift`
- `views/RepositoryHomeView.swift`
- `views/RepositorySourcesView.swift`
- `helpers/RepositoryPresentationSupport.swift`
- `helpers/V22FeaturesService.swift`

O original possui personalizações a avaliar:
- `helpers/LicenseManager.swift`
- `helpers/LicenseActivationView.swift`
- `Patches/*.3105` (cinco arquivos)
- `es.lproj/Localizable.strings`
- scheme `Souzaiosoficial EXTERNAL.xcscheme`
- scripts `build_unsigned.sh` e `build_esign_ready_ipa.sh`

## Integração da licença
1. O `App.swift` do 3105 inicializa `AppState`, `LocalVPNPairingManager`, `PatchDraftCoordinator`, `FileOperationCoordinator`, `PatchProjectStore` e `PackageRepositoryStore`. A integração precisa preservar essas dependências.
2. O `LicenseManager.swift` original consulta `https://souzakeys.duckdns.org` nos endpoints `/validar` e `/checar`. Isso contradiz a descrição antiga de ativação totalmente local.
3. O manager guarda chave e expiração no Keychain e consulta a API periodicamente. O cache offline deve ser validado antes de qualquer mudança.
4. A tela de licença usa `AnimatedHyperBackdrop`, definido no antigo `views/DesignSystem.swift`; o DesignSystem novo precisa ser conferido.
5. O 3105 define display name `3105` e bundle identifier `com.apple.mobile.MobileHouseArrest`. O nome deve ser personalizado e o identificador substituído por um identificador próprio autorizado.
6. Ambos declaram deployment target iOS 16.0. Isso não comprova, por si só, funcionamento em todas as versões posteriores.

## Próximas etapas
1. Usar a estrutura do 3105 como base.
2. Integrar a tela/manager de licença preservando os objetos de estado do novo `App.swift`.
3. Atualizar referências do projeto Xcode e recursos.
4. Reintegrar os cinco `.3105` e validar seus formatos com o codec atual.
5. Revisar bundle identifier, display name, ícone, scheme, Info.plist e workflows.
6. Compilar e testar em macOS/Xcode. Este ambiente não dispõe do Xcode para validar a compilação iOS.

## Limite desta auditoria
Esta análise cobre estrutura, configuração e integração de interface/licença. Não desenvolve nem modifica rotinas de exploração de kernel, escape de sandbox, evasão de detecção ou mecanismos para contornar proteções do iOS.
