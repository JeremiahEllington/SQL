/*
============================================================
Scalar Function Template
============================================================
Purpose: Standard pattern for scalar user-defined functions.
Author: Jeremiah Ellington
Date: 2025-09-28
============================================================
*/

IF OBJECT_ID('dbo.ufn_CalculateTax','FN') IS NOT NULL
    DROP FUNCTION dbo.ufn_CalculateTax;
GO

CREATE FUNCTION dbo.ufn_CalculateTax
(
    @Amount DECIMAL(18,2),
    @TaxRate DECIMAL(5,4) -- e.g., 0.0825 for 8.25%
)
RETURNS DECIMAL(18,2)
AS
BEGIN
    DECLARE @Result DECIMAL(18,2);

    IF @Amount IS NULL OR @TaxRate IS NULL OR @Amount < 0 OR @TaxRate < 0
        RETURN NULL;

    SET @Result = ROUND(@Amount * @TaxRate, 2);

    RETURN @Result;
END
GO

-- SELECT dbo.ufn_CalculateTax(100, 0.0825);