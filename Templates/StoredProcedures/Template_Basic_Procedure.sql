/*
============================================================
Stored Procedure Template - Basic Pattern
============================================================
Purpose: Provide a standard template for creating stored procedures.
Author: Jeremiah Ellington
Date: 2025-09-28
============================================================
*/

IF OBJECT_ID('dbo.usp_SampleProcedure','P') IS NOT NULL
    DROP PROCEDURE dbo.usp_SampleProcedure;
GO

CREATE PROCEDURE dbo.usp_SampleProcedure
    @Param1 INT,
    @Param2 NVARCHAR(50) = NULL,
    @StartDate DATE = NULL,
    @EndDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        -- Input validation
        IF @Param1 IS NULL OR @Param1 <= 0
        BEGIN
            RAISERROR('Param1 must be a positive integer',16,1);
            RETURN;
        END

        IF @StartDate IS NOT NULL AND @EndDate IS NOT NULL AND @StartDate > @EndDate
        BEGIN
            RAISERROR('@StartDate cannot be after @EndDate',16,1);
            RETURN;
        END

        -- Main query example
        SELECT 
            c.CustomerID,
            c.FirstName,
            c.LastName,
            o.OrderID,
            o.OrderDate,
            o.TotalAmount
        FROM dbo.Customers c
        INNER JOIN dbo.Orders o ON c.CustomerID = o.CustomerID
        WHERE c.CustomerID = @Param1
          AND (@Param2 IS NULL OR c.LastName = @Param2)
          AND (@StartDate IS NULL OR o.OrderDate >= @StartDate)
          AND (@EndDate IS NULL OR o.OrderDate <= @EndDate)
        ORDER BY o.OrderDate DESC;

    END TRY
    BEGIN CATCH
        DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
        DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
        DECLARE @ErrorState INT = ERROR_STATE();
        RAISERROR('Stored Procedure Error: %s', @ErrorSeverity, @ErrorState, @ErrorMessage);
    END CATCH
END
GO

-- EXEC dbo.usp_SampleProcedure @Param1 = 1, @Param2 = 'Smith';