ALTER PROCEDURE sp_CustomerRevenue
	 @FromYear INT       = NULL
	,@ToYear INT         = NULL
	,@Period VARCHAR(10) = NULL
	,@CustomerId INT     = NULL
AS
	SET NOCOUNT ON;

DECLARE  @TableSql  NVARCHAR(MAX)
		,@InsertSql NVARCHAR(MAX)
		,@CustSql   NVARCHAR(MAX)
		,@CustName  VARCHAR(MAX)
		,@TblName   VARCHAR(MAX)
		,@PeriodSql NVARCHAR(MAX)
		,@GroupSql  NVARCHAR(MAX)
		,@OrderSql  NVARCHAR(MAX);

-- Input validation
IF ISNULL(@Period, 'Y') NOT IN ('Month', 'M', 'Quarter', 'Q', 'Year', 'Y')
	BEGIN
		RAISERROR('Invalid period input', 16, 1);
		RETURN;
	END;

IF @CustomerId IS NOT NULL
	AND NOT EXISTS (SELECT 1 
			   FROM [Dimension].[Customer]
			   WHERE [Customer Key] = @CustomerId)
	BEGIN
		RAISERROR('Customer doesn''t exist', 16, 1);
		RETURN;
	END;

-- Handling of default values and prep of custom inputs
IF @FromYear IS NULL
	SET @FromYear = (SELECT MIN([Calendar Year]) FROM [Dimension].[Date]);

IF @ToYear IS NULL
	SET @ToYear = (SELECT MAX([Calendar Year]) FROM [Dimension].[Date]);

IF @CustomerId IS NULL
	BEGIN
		SET @CustSql = N'';
		SET @CustName = 'All'
	END
ELSE 
	BEGIN
		SET @CustSql = N' AND ord.[Customer Key] = ' + CAST(@CustomerId AS NVARCHAR(10));
		SET @CustName = (SELECT CONCAT(CAST([Customer Key] AS VARCHAR(10)), '_', TRIM([Customer])) 
						 FROM [Dimension].[Customer]
						 WHERE [Customer Key] = @CustomerId)
	END;

IF @Period IN ('Month', 'M')
	BEGIN
		SET @Period = 'M';
		SET @PeriodSql = N' CONCAT(dt.[Short Month], '' '', dt.[Calendar Year]) ';
		SET @GroupSql  = N', dt.[Calendar Month Number], dt.[Short Month] ';
		SET @OrderSql  = N', dt.[Calendar Month Number]';
	END
ELSE IF @Period IN ('Quarter', 'Q')
	BEGIN
		SET @Period = 'Q';
		SET @PeriodSql = N' CONCAT(''Q'', (dt.[Calendar Month Number] - 1) / 3 + 1, '' '', dt.[Calendar Year]) ';
		SET @GroupSql  = N', (dt.[Calendar Month Number] - 1) / 3 + 1 ';
		SET @OrderSql  = N', (dt.[Calendar Month Number] - 1) / 3 + 1';
	END
ELSE
	BEGIN
		SET @Period = 'Y';
		SET @PeriodSql = N' dt.[Calendar Year] ';
		SET @GroupSql  = N'';
		SET @OrderSql  = N'';
	END;

-- Prep of custom result table
SET @TblName = CONCAT(@CustName, '_', CAST(@FromYear AS VARCHAR(4)), '_', CAST(@ToYear AS VARCHAR(4)), '_', @Period);

SET @TableSql = N'DROP TABLE @TblName';

IF OBJECT_ID(@TblName) IS NOT NULL 
	EXEC sys.sp_executesql @TableSql, N'@TblName varchar(max)',
                   @TblName = @TblName;

-- Revenue calculation for the provided customer within the provided period
SET @InsertSql = N'SELECT 
				 [CustomerID] = ord.[Customer Key]
				,[CustomerName] = CAST(cust.[Customer] AS VARCHAR(50))
				,[Period] = CAST(' + @PeriodSql + N' AS VARCHAR(8))
				,[Revenue] = CAST(SUM(ord.[Quantity] * ord.[Unit Price]) AS NUMERIC(19,2))
			INTO ' + QUOTENAME(@TblName) + 
			N' FROM [Fact].[Order] ord
			JOIN [Dimension].[Customer] cust
				ON ord.[Customer Key] = cust.[Customer Key]
			JOIN [Dimension].[Date] dt
				ON ord.[Order Date Key] = dt.[Date]
			WHERE dt.[Calendar Year] BETWEEN @FromYear AND @ToYear' + @CustSql +
			N' GROUP BY ord.[Customer Key], cust.[Customer], dt.[Calendar Year]' + @GroupSql +
			N' ORDER BY ord.[Customer Key], dt.[Calendar Year]' + @OrderSql;

EXEC sys.sp_executesql @InsertSql, N'@FromYear int, @ToYear int, @TblName varchar(max)',
                   @FromYear = @FromYear, @ToYear = @ToYear, @TblName = @TblName;


-- Procedure use
EXEC sp_CustomerRevenue 
	 @FromYear = 2014
	,@ToYear = 2015
	,@Period = 'M'
	,@CustomerId = 4