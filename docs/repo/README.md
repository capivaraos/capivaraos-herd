# Repositório de atualizações do Herd — arquitetura, layout e operação

- **Jira:** PROD-104 (infra do repo assinado) + PROD-105 (pacote `capivaraos-herd-repos`)
- **Épico:** PROD-102 (atualização automática do servidor)
- **Relaciona:** FEAT-112 (repo do desktop — **mesma fundação**, não duplicar), reference_domains_org_com

## Problema que isto resolve

Um Herd instalado recebia updates **do Fedora**, mas **nunca os nossos**
(`capivaraos-herd-*`, `herd-harden`, `herd-compliance-scan`, correções de
segurança): os RPMs próprios só existiam **offline dentro da ISO**, e o sistema
instalado não tinha repositório nenhum configurado. Sem isto, "atualização
automática" e "compliance contínuo" não existem de verdade.

## Modelo de confiança (a decisão central)

**A integridade vem da assinatura, não do host.** Assinamos com uma chave GPG
**nossa**, cuja privada fica **offline** (HSM/cofre — ver `keys/README.md`):

- cada **RPM** é assinado (`rpm --addsign`);
- o **índice** do repo (`repodata/repomd.xml`) é assinado (`repomd.xml.asc`);
- o cliente valida os dois: `gpgcheck=1` (pacote) + `repo_gpgcheck=1` (metadado).

Consequência prática: **o servidor de arquivos pode ser um bucket barato + CDN
pública** e ainda assim um invasor que comprometa o host **não** consegue
empurrar update malicioso (a assinatura não bate). Isso é exatamente o que um
auditor quer ver documentado (cadeia de integridade fim-a-fim).

## Onde hospedar

| Fase | Host | Por quê |
|---|---|---|
| **Bootstrap** | **Fedora Copr** | grátis, já assina e serve; bom para as primeiras builds/testes sem montar infra nem billing. |
| **Produção (decidido)** | **`repo.capivaraos.org`** = **Cloudflare R2** + CDN Cloudflare | um repo é "muito download, pouco storage": o **egress grátis/ilimitado do R2** ganha. Free tier (10 GB + egress zero) cobre o nosso caso; acima disso são centavos de storage, nunca banda. É só arquivos estáticos. |

Backblaze B2 foi avaliado (storage mais barato) mas o egress só é grátis até 3× o
armazenado — precisaria da CDN Cloudflare na frente para zerar banda, mais peças
para configurar. Por isso o padrão é **R2**. O R2 exige conta Cloudflare com forma
de pagamento cadastrada mesmo no free tier.

> **Quando o host de produção é necessário (e por que adiar não atrasa nada):**
> só no **lançamento**. Durante o desenvolvimento, `publish-repo.sh add`/`promote`
> montam e assinam o repo **localmente** (`out/repo/…`) e testamos instalação por
> `file://` ou `python -m http.server`; para um teste "online" há o **Copr**
> (grátis, sem cartão). A confiança vem da assinatura, não do host, e o `baseurl`
> aponta para o domínio **nosso** (`repo.capivaraos.org`) — dá para apontar esse
> DNS a R2/B2/qualquer host **depois**, sem mexer em nenhum pacote. **Decisão:**
> R2 é o alvo de produção (melhor escolha técnica), mas a ativação (e o cartão)
> fica **adiada** para o lançamento. O pré-requisito que realmente destrava o
> desenvolvimento é a **chave GPG** (`keys/gen-signing-key.sh`), não o host.

### Setup do R2 (produção)

1. Criar o bucket (ex.: `capivaraos-herd`) no R2.
2. Ligar **custom domain** `repo.capivaraos.org` no bucket (o R2 serve com a CDN
   Cloudflare automaticamente).
3. Configurar o `rclone` uma vez: `rclone config` → tipo `s3`, provider
   `Cloudflare`, endpoint do R2 e as chaves de acesso. Nome do remote = `r2`
   (ou ajuste `HERD_RCLONE_REMOTE` no `publish-repo.sh`).
4. **Cache na CDN (importante):** o `publish-repo.sh` já sobe os **RPMs** como
   imutáveis (`max-age` longo) e o **`repodata/`** com cache curto + revalidação —
   assim a borda nunca serve um índice velho apontando para um pacote que já
   mudou de canal. Ajustável via `HERD_CACHE_RPM` / `HERD_CACHE_META`.

**Domínio (decisão fechada, ver reference_domains_org_com):** o repositório
**grátis/Community** vive no **`.org`** (`repo.capivaraos.org`). Um usuário da
comunidade **nunca** precisa tocar o domínio comercial para receber correção de
segurança. O repositório **Enterprise gated por licença** é que fica no
**`.com`** (`repo.capivaraos.com`) — trilha PROD-83/PROD-85, futura.

## Layout

```
repo.capivaraos.org/
└── herd/
    └── f44/                 # base Fedora (= $releasever no cliente)
        └── x86_64/          # (e aarch64/ quando publicarmos ARM)
            ├── testing/      # canal de QA (repo enabled=0 no cliente)
            │   ├── *.rpm
            │   └── repodata/{repomd.xml, repomd.xml.asc, ...}
            └── stable/       # canal de produção (enabled=1)
                ├── *.rpm
                └── repodata/{repomd.xml, repomd.xml.asc, ...}
```

Por que **por base Fedora** (`f44`) e não pela versão do produto (1.0.1): o que
determina compatibilidade de RPM é a base. No cliente, `$releasever` resolve para
`44` (via `system-release(releasever)` do `fedora-release`, **não** pelo
`VERSION_ID` do os-release) e num `dnf system-upgrade --releasever=45` vira `45`
— o `baseurl` aponta sozinho para `herd/f45/`, sem editar o `.repo`.

## Fluxo de publicação

```
build RPM  →  add ao TESTING  →  QA em VM  →  PROMOTE p/ STABLE  →  upload (CDN)
```

Tudo via `publish-repo.sh` (raiz do repo):

```bash
# 1) assina + coloca no testing + gera/assina o índice
./publish-repo.sh add     --rel 44 --arch x86_64 --channel testing ~/rpmbuild/RPMS/noarch/*.rpm
# 2) (após validar em VM) promove para stable
./publish-repo.sh promote --rel 44 --arch x86_64
# 3) sobe a árvore para o object storage (rclone)
./publish-repo.sh upload  --rel 44 --arch x86_64
```

Ordem no upload importa: sobem-se os **RPMs antes** do `repodata/`, para o índice
nunca apontar (mesmo que por segundos) para um pacote ainda ausente.

## O cliente (pacote `capivaraos-herd-repos`)

- Instala `/etc/yum.repos.d/capivaraos-herd.repo` (canais `stable` ligado e
  `testing` desligado) e a chave pública em `/etc/pki/rpm-gpg/`, importada no
  chaveiro do rpm no `%post` (sem prompt no primeiro update).
- Embarcado nos dois caminhos de build: `%packages` do kickstart e blueprint
  osbuild.
- **Consumo automático:** com `dnf-automatic` (PROD-106) o servidor aplica as
  atualizações de segurança sozinho; na UI, a página de Updates do Herd Control
  (PROD-108) mostra/aplica/agenda.

## Ordem de implantação (guardrail)

**Não embarcar o `capivaraos-herd-repos` numa ISO antes de
`repo.capivaraos.org/herd/...` estar no ar** — senão todo `dnf` no sistema
instalado avisa "repositório inacessível". Sequência correta:

1. gerar a chave (offline) e commitar a pública;
2. publicar (pelo menos o índice vazio assinado) em `stable`;
3. só então cortar uma ISO que inclua o pacote de repos.

## Como testar de ponta a ponta (antes de publicar)

Mecânica validável **sem** a chave de produção, usando uma **chave descartável**:
gerar par temporário → assinar um RPM de teste → `createrepo_c` + assinar
`repomd.xml` → subir a árvore num diretório local → em uma VM/contêiner Fedora 44,
instalar o `capivaraos-herd-repos`, apontar o `baseurl` para o diretório e rodar
`dnf --refresh install/upgrade` confirmando que a assinatura valida e que um
pacote adulterado é **recusado**. Só depois a chave real entra na cerimônia
offline. (Nada vai para produção sem esse teste — ver feedback_qa_test_before_publish.)
