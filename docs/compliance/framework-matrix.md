# Matriz de compliance do Herd — frameworks → controles → perfis

- **Jira:** PROD-93 (fundação do épico PROD-92) · relaciona FEAT-94
- **Fonte:** `hardening/scap/ssg-fedora-ds.xml` (SCAP Security Guide para Fedora, redistribuído no Herd). Números medidos neste datastream em 2026-08-28.
- **Status:** documento vivo — atualizar quando o SSG for atualizado ou quando criarmos tailorings próprios.

> **Guardrail de linguagem (vale sobretudo mirando auditores):** o Herd é
> **"compliance-ready / pronto para conformidade"** — entrega **controles técnicos
> + evidência** que reduzem o trabalho. **NUNCA** "certificado ISO/PCI/SOC 2": a
> certificação é um processo da organização (jurídico + processo + auditoria), não
> algo que o SO "é". Sobre FIPS: dizemos **"opera em modo FIPS / FIPS-ready"**,
> **nunca "FIPS 140 validado/certificado"** — o Fedora não tem módulos CMVP
> validados (só RHEL/derivados).

## Como o Herd cobre um framework — dois mecanismos

1. **Perfil executável** — o SSG traz um *profile* pronto para Fedora. O Herd
   **avalia** (`herd-compliance-scan <perfil>`) e **aplica** (`herd-harden <perfil>`)
   direto. É o caminho mais forte (scan + remediação + evidência).
2. **Referência cruzada** — mesmo sem um *profile* dedicado, **cada regra do SSG
   carrega os IDs de controle** de dezenas de frameworks (ISO, NIST, HIPAA, PCI,
   STIG…). Isso permite (a) **mapear** um scan para vários frameworks de uma vez
   (cross-mapping, PROD-95) e (b) **construir um perfil próprio** ("tailoring")
   selecionando as regras que carregam aquele framework (PROD-94).

Um terceiro grupo — **SOC 2, FedRAMP, LGPD, CRA** — é **processo/jurídico**: não
existe "profile" que torne o SO conforme; o Herd entrega **evidência e controles
técnicos** que a organização usa na sua auditoria/adequação.

## Tabela A — Perfis executáveis HOJE (scan + hardening)

Prontos no datastream para Fedora; `herd-compliance-scan`/`herd-harden` já os
rodam. (Regras selecionadas medidas no `ssg-fedora-ds.xml`.)

| Perfil (id SSG) | Alias Herd | Regras | Para quê |
|---|---|---:|---|
| `standard` | `standard` | 76 | Baseline sensato (default do Herd) |
| `ospp` | `ospp` | 208 | Protection Profile (NIAP/US Gov); **caminho mais próximo de STIG** no Fedora |
| `pci-dss` | `pci` | 121 | PCI-DSS (cartões) |
| `cis_server_l1` | `cis-l1` | 324 | CIS Benchmark **Nível 1** servidor |
| `cis` | `cis-l2` | 438 | CIS Benchmark **Nível 2** (mais rígido) |

> Não há **profile STIG** para Fedora (o STIG é publicado só para RHEL). Para
> requisito STIG/DISA, o `ospp` é o substituto prático + o cross-map dos SRG (ver
> Tabela B).

## Tabela B — Frameworks por referência cruzada (a base do cross-mapping)

Todos abaixo **aparecem nas referências das regras** do datastream Fedora — ou
seja, um único scan já traz o mapeamento. "Regras" = nº de referências àquele
sistema no datastream (aproxima quantas regras o citam).

| Framework | No datastream | Como o Herd entrega | Alvo |
|---|---:|---|---|
| **ISO/IEC 27001** | 6680 | cross-map hoje; tailoring "Herd ISO 27001" possível | PROD-95 → PROD-94 |
| **HIPAA** (45 CFR Security Rule) | 2436 | cross-map hoje; tailoring possível | PROD-95 → PROD-94 |
| **NIST SP 800-53** (r4) | 2018 | cross-map hoje; base técnica de FedRAMP | PROD-95 |
| **NIST SP 800-171** | 1452 | cross-map hoje; tailoring "Herd 800-171" possível | PROD-95 → PROD-94 |
| **DISA STIG / SRG** | 1547 | cross-map; perfil executável = `ospp` | Tabela A + PROD-95 |
| **NIST CSF** | ~2009 | cross-map | PROD-95 |
| **CIS Controls** (v8) | 3937 | cross-map; perfis executáveis = `cis*` | Tabela A + PROD-95 |
| **PCI-DSS v4.0 / v3.2.1** | 561 / 248 | perfil executável `pci-dss` + cross-map | Tabela A |
| **ANSSI** (FR) | 361 | cross-map | PROD-95 |
| **ACSC ISM** (AU) | 422 | cross-map | PROD-95 |
| **NERC CIP** | 1218 | cross-map (setor elétrico) | PROD-95 |
| **CJIS** (FBI) | 125 | cross-map | PROD-95 |
| **BSI Grundschutz** (DE) | 15 | cross-map | PROD-95 |
| **ISA/IEC 62443** (OT/industrial) | 5530 | cross-map | PROD-95 |
| **COBIT** | 4779 | cross-map (governança) | PROD-95 |
| **FIPS 140-2** | 12 | **modo FIPS** (`fips=1`), não profile; ver guardrail | doc segurança |

## Tabela C — Processo/jurídico (evidência, não "profile")

Não há *profile* que torne o SO conforme; o Herd entrega **controles + evidência**
e a organização conduz a certificação/adequação. Candidatos a **framework packs
pagos** curados (PROD-101).

| Framework | Natureza | Papel do Herd |
|---|---|---|
| **SOC 2** | Atestação (Trust Services Criteria) | Mapear controles técnicos → TSC; fornecer evidência (audit pack, PROD-97) |
| **FedRAMP** | Programa de autorização US Gov sobre NIST 800-53 | Cross-map 800-53 cobre a maioria dos controles técnicos; autorização é processo |
| **LGPD** (BR) | Lei de proteção de dados | Tailoring próprio "Herd LGPD" (FEAT-98/PROD-94) + templates; diferencial exclusivo |
| **CRA** (EU) | Lei (SBOM, secure-by-design, reporte de vuln) | SBOM + provenance commit→deploy + evidência (FEAT-95/96, PROD-101) |

## Leitura estratégica (o que a matriz destrava)

- **Já temos MUITO de graça:** 5 perfis executáveis (baseline, OSPP, PCI, CIS L1/L2)
  + referência cruzada a ~16 frameworks. É a base do posicionamento "compliance
  ágil, fácil e grátis".
- **Cross-mapping (PROD-95)** é a vitória barata: um scan → resultado em ISO/NIST/
  HIPAA/PCI/STIG ao mesmo tempo. "Este 1 fix fecha lacuna em N normas."
- **Tailorings próprios (PROD-94)** viram perfis executáveis para frameworks sem
  profile Fedora (ISO 27001, NIST 800-171, LGPD) — **diferencial que ninguém
  entrega pronto numa distro**.
- **Packs de processo (SOC 2/FedRAMP/CRA)** = serviço pago curado + evidência
  (audit pack / evidência assinada), não promessa de "certificado".

## Como reproduzir os números

```bash
# perfis disponíveis (na imagem do Herd)
herd-compliance-scan --list

# contagem de regras por perfil e referências (a partir do datastream)
grep -oP '<xccdf[^>]*:Profile id="[^"]*"' hardening/scap/ssg-fedora-ds.xml
grep -oP 'href="[^"]*"' hardening/scap/ssg-fedora-ds.xml | sort | uniq -c | sort -rn
```
