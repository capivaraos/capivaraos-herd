# Chave de assinatura do repositório do Herd

Este diretório guarda **apenas a chave pública** de assinatura do repositório de
atualizações do CapivaraOS Herd (PROD-104/PROD-105). A confiança dos updates
**não depende do host** que serve os arquivos: `gpgcheck` + `repo_gpgcheck`
rejeitam qualquer pacote ou metadado que não esteja assinado por esta chave —
mesmo que o CDN/servidor seja comprometido.

## Arquivos

| Arquivo | Commitar? | O que é |
|---|---|---|
| `gen-signing-key.sh` | sim | Cerimônia (offline) que gera o par de chaves. |
| `RPM-GPG-KEY-capivaraos-herd` | **sim** | Chave **pública** (ASCII). Distribuída pelo pacote `capivaraos-herd-repos`. Gerada pelo script; ainda não existe no repo. |
| chave **privada** | **NUNCA** | Fica offline (HSM/YubiKey/cofre). Jamais neste repositório nem no servidor do repo. |

## Modelo de confiança (por que é seguro)

- A chave **privada** assina: cada RPM (`rpm --addsign`) e o `repomd.xml` do
  repositório (assinatura destacada `repomd.xml.asc`).
- A chave **pública** viaja no pacote `capivaraos-herd-repos`, é instalada em
  `/etc/pki/rpm-gpg/RPM-GPG-KEY-capivaraos-herd` e importada no chaveiro do rpm.
- No cliente, `gpgcheck=1` valida a assinatura de cada pacote e `repo_gpgcheck=1`
  valida a assinatura do índice do repo. Update forjado/adulterado é recusado.
- Por isso o **host dos arquivos é irrelevante** para a integridade: object
  storage barato + CDN servem tranquilos (ver `docs/repo/README.md`).

## Primeira geração (uma vez, OFFLINE)

```bash
./keys/gen-signing-key.sh
```

O script gera RSA 4096, exporta a **pública** para
`keys/RPM-GPG-KEY-capivaraos-herd` (commite este arquivo) e a **privada** para um
arquivo no seu `$HOME` que você deve **mover para o cofre/HSM e apagar com
`shred`**. Publique o **fingerprint** na página de Segurança do site/docs para
os clientes poderem conferir.

## Assinatura na publicação

Na máquina que publica o repositório (ver `publish-repo.sh`):

```bash
# importe a privada só na hora (ou use o agente do YubiKey/HSM)
gpg --import /caminho/seguro/privada.asc
# diga ao rpm qual chave usar
cat >> ~/.rpmmacros <<'EOF'
%_gpg_name CapivaraOS Herd (repo signing key)
%_gpg_digest_algo sha512
EOF
```

## Rotação / comprometimento

- **Rotação planejada:** gere uma chave nova, passe a assinar com as **duas**
  (nova + antiga) por um período, distribua a nova pública num update do
  `capivaraos-herd-repos`, e só então aposente a antiga.
- **Comprometimento:** revogue (publique o certificado de revogação), gere nova
  chave, force o update do `capivaraos-herd-repos` com a nova pública e avise na
  página de Segurança. Por isso o certificado de revogação também deve ser
  gerado e guardado junto da privada.

> Nunca confunda esta chave (assinatura de **repositório/RPM**, RSA) com a chave
> de **licença** do Herd Control Enterprise (ed25519, no daemon Go — ver o ADR
> 0001). São propósitos e cadeias distintos.
