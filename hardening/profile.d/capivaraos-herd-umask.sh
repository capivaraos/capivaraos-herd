# CapivaraOS HERD — umask restritivo para sessões de login (PROD-41).
# 027 = arquivos novos não ficam legíveis por "outros" (o grupo lê; outros nada).
# Cobre logins interativos (ssh/console), que é o uso do HERD (headless). A
# política system-wide via login.defs/pam_umask fica para o perfil CIS completo.
umask 027
