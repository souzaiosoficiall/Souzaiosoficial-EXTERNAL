# Notas da migração — Souzaiosoficial EXTERNAL / 3105 v2.2

## Origem dos componentes
- Interface visual e identidade da marca: `original.zip`.
- Fluxo de licença: `LicenseManager.swift` e `LicenseActivationView.swift` do original.
- Target do app, política atual de suporte, LocalDevVPN, Device Pairing, resolução do contêiner, transações e serviços de dispositivo: mantidos a partir de `3105-main.zip`.
- Pacotes `.3105` e AppIcon originais: copiados de `original.zip`.

## Comportamentos importantes
A aba Perfil agora abre a `PairingVPNView` da base nova. Isso é importante porque a base 2.2 usa o estado de pareamento/túnel como uma das rotas de acesso ao dispositivo. A `ContentView` original usa a única instância de `PatchProjectStore` criada no `App`, em vez de criar uma segunda instância independente.

Os cinco pacotes que vêm junto com o app são copiados para `Application Support/PatchProjects` no início da biblioteca e desbloqueados com a senha interna do projeto original (`3105`) somente quando o nome do arquivo corresponde a um pacote conhecido. Pacotes protegidos importados pelo usuário continuam exigindo a senha própria.

O botão da janela de desbloqueio antiga apenas fechava a janela. Nesta migração, ele foi ligado a `PatchProjectStore.unlock(password:)`.

## Limites de execução
- O código de suporte e resolução de contêiner da base nova foi mantido.
- A interface diferencia `containerAccessUnavailable` de `targetAppUnavailable`.
- Um contêiner temporário/staged não é tratado como contêiner real; o `DevicePatchService` da base nova continua recusando operações quando só há um contêiner staged.
- O workflow não injeta entitlements privados de no-sandbox nem faz assinatura ad-hoc com esses privilégios.
- O IPA sem assinatura é apenas um artefato de build. Ainda precisa ser assinado por um método legítimo para instalar; uma assinatura comum não concede acesso privado ao contêiner de outro app.

## Verificações
- Estrutura do projeto, plist, referências de recursos e sintaxe Swift foram verificadas.
- Não foi possível executar Xcode nem testar o iOS 27.2 neste ambiente.
