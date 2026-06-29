-- =====================================================================
-- SUGU - Financeiro e de Compras - Functions, Triggers e Procedures
-- Criadas ANTES da carga de dados, para que as triggers atuem na insercao.
-- =====================================================================
USE sugu_financeiro;

-- ============================ FUNCTIONS ==============================
DELIMITER $$

CREATE FUNCTION fn_saldo_orcamento(p_id_orcamento INT)
RETURNS DECIMAL(15,2) READS SQL DATA
BEGIN
  DECLARE v_saldo DECIMAL(15,2);
  SELECT valor_total - valor_consumido INTO v_saldo
    FROM ORCAMENTO WHERE id_orcamento = p_id_orcamento;
  RETURN COALESCE(v_saldo, 0);
END $$

CREATE FUNCTION fn_total_pago_nota(p_id_nota INT)
RETURNS DECIMAL(15,2) READS SQL DATA
BEGIN
  DECLARE v_total DECIMAL(15,2);
  SELECT COALESCE(SUM(valor), 0) INTO v_total
    FROM PAGAMENTO WHERE id_nota = p_id_nota;
  RETURN v_total;
END $$

CREATE FUNCTION fn_saldo_nota(p_id_nota INT)
RETURNS DECIMAL(15,2) READS SQL DATA
BEGIN
  DECLARE v_valor DECIMAL(15,2);
  SELECT valor INTO v_valor FROM NOTA_FISCAL WHERE id_nota = p_id_nota;
  RETURN COALESCE(v_valor, 0) - fn_total_pago_nota(p_id_nota);
END $$

CREATE FUNCTION fn_qtd_propostas(p_id_licitacao INT)
RETURNS INT READS SQL DATA
BEGIN
  DECLARE v_qtd INT;
  SELECT COUNT(*) INTO v_qtd FROM PROPOSTA WHERE id_licitacao = p_id_licitacao;
  RETURN v_qtd;
END $$

CREATE FUNCTION fn_fornecedor_regular(p_id_fornecedor INT)
RETURNS BOOLEAN READS SQL DATA
BEGIN
  DECLARE v_reg VARCHAR(15);
  SELECT regularidade_fiscal INTO v_reg
    FROM FORNECEDOR WHERE id_fornecedor = p_id_fornecedor;
  RETURN (v_reg = 'REGULAR');
END $$

DELIMITER ;

-- ============================ TRIGGERS ===============================
DELIMITER $$

CREATE TRIGGER trg_compra_before_insert
BEFORE INSERT ON COMPRA FOR EACH ROW
BEGIN
  DECLARE v_saldo DECIMAL(15,2);
  IF NOT fn_fornecedor_regular(NEW.id_fornecedor) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Fornecedor sem regularidade fiscal: compra bloqueada.';
  END IF;
  SET v_saldo = fn_saldo_orcamento(NEW.id_orcamento);
  IF NEW.valor_total > v_saldo THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Saldo orcamentario insuficiente para a compra.';
  END IF;
END $$

CREATE TRIGGER trg_compra_after_insert
AFTER INSERT ON COMPRA FOR EACH ROW
BEGIN
  UPDATE ORCAMENTO SET valor_consumido = valor_consumido + NEW.valor_total
    WHERE id_orcamento = NEW.id_orcamento;
END $$

CREATE TRIGGER trg_compra_after_delete
AFTER DELETE ON COMPRA FOR EACH ROW
BEGIN
  UPDATE ORCAMENTO SET valor_consumido = valor_consumido - OLD.valor_total
    WHERE id_orcamento = OLD.id_orcamento;
END $$

CREATE TRIGGER trg_proposta_before_insert
BEFORE INSERT ON PROPOSTA FOR EACH ROW
BEGIN
  DECLARE v_status VARCHAR(15);
  SELECT status INTO v_status FROM LICITACAO WHERE id_licitacao = NEW.id_licitacao;
  IF v_status NOT IN ('ABERTA','EM_ANALISE') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Licitacao nao esta aberta para receber propostas.';
  END IF;
END $$

CREATE TRIGGER trg_pagamento_before_insert
BEFORE INSERT ON PAGAMENTO FOR EACH ROW
BEGIN
  DECLARE v_saldo DECIMAL(15,2);
  SET v_saldo = fn_saldo_nota(NEW.id_nota);
  IF NEW.valor > v_saldo THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Pagamento excede o saldo em aberto da nota fiscal.';
  END IF;
END $$

DELIMITER ;

-- ============================ PROCEDURES =============================
DELIMITER $$

CREATE PROCEDURE sp_registrar_compra(
  IN p_data DATE, IN p_valor DECIMAL(15,2), IN p_id_fornecedor INT,
  IN p_id_licitacao INT, IN p_id_orcamento INT, OUT p_id_compra INT)
BEGIN
  INSERT INTO COMPRA (data, valor_total, id_fornecedor, id_licitacao, id_orcamento)
  VALUES (p_data, p_valor, p_id_fornecedor, p_id_licitacao, p_id_orcamento);
  SET p_id_compra = LAST_INSERT_ID();
END $$

CREATE PROCEDURE sp_homologar_licitacao(IN p_id_licitacao INT, IN p_id_proposta INT)
BEGIN
  DECLARE v_existe INT;
  SELECT COUNT(*) INTO v_existe FROM PROPOSTA
    WHERE id_proposta = p_id_proposta AND id_licitacao = p_id_licitacao;
  IF v_existe = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Proposta informada nao pertence a esta licitacao.';
  END IF;
  UPDATE PROPOSTA SET vencedora = (id_proposta = p_id_proposta) WHERE id_licitacao = p_id_licitacao;
  UPDATE LICITACAO SET status = 'HOMOLOGADA' WHERE id_licitacao = p_id_licitacao;
END $$

CREATE PROCEDURE sp_registrar_pagamento(
  IN p_id_nota INT, IN p_valor DECIMAL(15,2), IN p_forma VARCHAR(15), IN p_data DATE)
BEGIN
  INSERT INTO PAGAMENTO (data, valor, forma_pagamento, id_nota)
  VALUES (p_data, p_valor, p_forma, p_id_nota);
END $$

CREATE PROCEDURE sp_relatorio_orcamento(IN p_ano INT)
BEGIN
  SELECT id_orcamento, setor, projeto, valor_total, valor_consumido,
         fn_saldo_orcamento(id_orcamento) AS saldo,
         ROUND(valor_consumido / NULLIF(valor_total,0) * 100, 1) AS pct_consumido
    FROM ORCAMENTO WHERE ano = p_ano ORDER BY saldo ASC;
END $$

DELIMITER ;
