# Contribuindo · Contributing

Obrigado pelo interesse no **CapivaraOS HERD**! Contribuições da comunidade são
bem-vindas: relatos de bug, melhorias na documentação, correções e novas ideias.

> 🇬🇧 English summary below.

## Como contribuir (PT)

- **Encontrou um bug ou tem uma ideia?** Abra uma
  [issue](https://github.com/capivaraos/capivaraos-herd/issues) usando os modelos
  disponíveis.
- **Vulnerabilidade de segurança?** **Não** abra issue pública — siga o
  [SECURITY.md](SECURITY.md).
- **Quer enviar código?**
  1. Faça um _fork_ e crie um branch a partir da `main`.
  2. Faça suas mudanças (veja o [README](README.md) para buildar as imagens/RPMs).
  3. Descreva claramente o _que_ e o _porquê_ no _pull request_.
  4. Um mantenedor revisa e responde.

### Boas práticas

- Mudanças pequenas e focadas são mais fáceis de revisar.
- Teste o que puder (ex.: reconstrua o RPM/imagem afetada) antes de enviar.
- Documentação também é contribuição — o conteúdo vive em
  [capivaraos-docs](https://github.com/capivaraos/capivaraos-docs).

### Fluxo de trabalho — branch + PR (regra do projeto)

Para **qualidade, rastreabilidade e auditoria**, todo o trabalho — **inclusive dos
mantenedores** — segue o mesmo fluxo. Não se faz `push` direto na `main`.

1. **Branch a partir da `main`**, com nome descritivo:
   `feat/<área>-<resumo>`, `fix/<bug>`, `chore/<tarefa>`, `docs/<assunto>`.
2. **Commits pequenos e coesos**, com mensagem explicando _o quê_ e _porquê_
   (imperativo). Referencie o ticket do Jira quando houver (ex.: `PROD-106`).
3. **Abra um Pull Request** para a `main`. O CI (ex.: ShellCheck) roda no PR;
   deixe-o **verde** antes de mesclar.
4. **A `main` fica sempre coerente e "releasável".** Um _release_ é uma **tag**
   (ex.: `herd-1.0.1`) + a imagem publicada — nunca "o que estiver na `main`"
   (ver a seção *Como funcionam os releases* no [README](README.md)).
5. **Segurança:** nunca commitar segredos/chaves privadas; o histórico é varrido
   (gitleaks) e a push protection está ativa.

> A `main` é protegida: PRs são o único caminho de entrada. Isso vale para os
> mantenedores também — é o que sustenta a auditabilidade do projeto.

### Licença das contribuições

Ao contribuir, você concorda em licenciar seu código sob a **GPLv3** (ver
[LICENSE](LICENSE)). O nome e o logotipo "CapivaraOS" são marca do projeto — ver
[TRADEMARK.md](TRADEMARK.md).

Seja respeitoso: seguimos um [Código de Conduta](CODE_OF_CONDUCT.md).

---

## How to contribute (EN)

- **Found a bug or have an idea?** Open an
  [issue](https://github.com/capivaraos/capivaraos-herd/issues) using the
  templates.
- **Security vulnerability?** Do **not** open a public issue — follow
  [SECURITY.md](SECURITY.md).
- **Want to send code?** Fork, branch from `main`, make focused changes (see the
  [README](README.md) to build images/RPMs), and open a pull request explaining
  _what_ and _why_. A maintainer will review.

**Workflow — branch + PR (project rule):** all work — **maintainers included** —
goes through a branch off `main` and a pull request; **no direct pushes to
`main`**. Keep commits small and focused (reference the Jira ticket when there is
one), let CI pass, and keep `main` releasable — a _release_ is a **tag**
(e.g. `herd-1.0.1`) plus the published image, never "whatever is on `main`" (see
*Como funcionam os releases* in the [README](README.md)). Never commit secrets.

By contributing, you agree to license your code under **GPLv3** (see
[LICENSE](LICENSE)); the "CapivaraOS" name and logo are the project's trademark
(see [TRADEMARK.md](TRADEMARK.md)). Please follow our
[Code of Conduct](CODE_OF_CONDUCT.md).
