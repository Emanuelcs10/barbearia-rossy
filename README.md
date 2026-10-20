# Barbearia Rossy 💈

Site de agendamento com Vite, JavaScript e Supabase.

## Instalação
1. Crie um projeto em https://supabase.com e abra **SQL Editor**.
2. Cole e execute o conteúdo de `supabase/schema.sql`.
3. Em **Authentication > Users**, crie o usuário do Rossy com e-mail e senha. Desative cadastro público por e-mail nas configurações de Auth se não precisar de novos usuários.
4. No **SQL Editor**, execute, trocando pelo e-mail real:
   ```sql
   insert into public.admins(user_id)
   select id from auth.users where email = 'EMAIL_DO_ROSSY';
   ```
5. Copie `.env.example` para `.env` e preencha a URL e a chave **anon/publishable** em **Project Settings > API**. **Nunca use service_role no frontend.**
6. No terminal, dentro da pasta do projeto:
   ```bash
   npm install
   npm run dev
   ```
7. Abra o endereço mostrado no terminal. Para o painel administrativo, clique em **Área do barbeiro**.

## Personalização
- Serviços e preços: painel administrativo, aba Serviços.
- Horários: no Supabase, edite `shop_settings.weekly_hours` (0=domingo, 1=segunda, ..., 6=sábado). Exemplo de expediente por dia: `[["09:00","12:00"],["13:00","18:00"]]`.
- Os horários estão configurados para o fuso **America/Fortaleza**. Se publicar em outro fuso, ajuste a função SQL e a interface.
- Os preços e serviços iniciais são **exemplos**, não valores oficiais da barbearia.

## Observações de segurança
- Agendamentos públicos são criados exclusivamente por função SQL que valida serviço, horário, telefone e conflito. A restrição de exclusão impede sobreposição de reservas simultâneas.
- O público só consulta intervalos ocupados, nunca nomes e telefones de clientes.
- Para uso público em grande escala, recomenda-se adicionar CAPTCHA, rate limiting na borda e políticas de retenção de dados/LGPD.
- Esta primeira versão não envia mensagens automáticas via WhatsApp nem processa pagamentos.
- Reservas concluídas continuam bloqueando aquele horário; reservas canceladas liberam o intervalo.
