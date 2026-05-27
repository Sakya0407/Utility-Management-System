USE master;
GO


IF EXISTS (SELECT name FROM sys.databases WHERE name = 'UtilityManagementDB')
BEGIN
    ALTER DATABASE UtilityManagementDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE UtilityManagementDB;
END
GO

CREATE DATABASE UtilityManagementDB;
GO

USE UtilityManagementDB;
GO



-- 1. UTILITY TYPE TABLE
CREATE TABLE UtilityType (
    UtilityTypeID INT PRIMARY KEY IDENTITY(1,1),
    UtilityName NVARCHAR(50) NOT NULL UNIQUE,
    UnitOfMeasurement NVARCHAR(20) NOT NULL,
    Description NVARCHAR(200),
    CreatedDate DATETIME DEFAULT GETDATE()
);

-- 2. TARIFF PLAN TABLE
CREATE TABLE TariffPlan (
    TariffID INT PRIMARY KEY IDENTITY(1,1),
    UtilityTypeID INT NOT NULL,
    PlanName NVARCHAR(100) NOT NULL,
    CustomerType NVARCHAR(50) NOT NULL,
    RatePerUnit DECIMAL(10,2) NOT NULL,
    FixedCharge DECIMAL(10,2) DEFAULT 0,
    EffectiveFromDate DATE NOT NULL,
    EffectiveToDate DATE,
    IsActive BIT DEFAULT 1,
    FOREIGN KEY (UtilityTypeID) REFERENCES UtilityType(UtilityTypeID)
);

-- 3. CUSTOMER TABLE
CREATE TABLE Customer (
    CustomerID INT PRIMARY KEY IDENTITY(1,1),
    CustomerName NVARCHAR(100) NOT NULL,
    CustomerType NVARCHAR(50) NOT NULL CHECK (CustomerType IN ('Residential', 'Commercial', 'Industrial')),
    Address NVARCHAR(200) NOT NULL,
    Phone NVARCHAR(15) NOT NULL,
    Email NVARCHAR(100),
    RegistrationDate DATETIME DEFAULT GETDATE(),
    Status NVARCHAR(20) DEFAULT 'Active' CHECK (Status IN ('Active', 'Inactive', 'Suspended'))
);

-- 4. METER TABLE
CREATE TABLE Meter (
    MeterID INT PRIMARY KEY IDENTITY(1,1),
    CustomerID INT NOT NULL,
    UtilityTypeID INT NOT NULL,
    MeterNumber NVARCHAR(50) NOT NULL UNIQUE,
    InstallationDate DATE NOT NULL,
    LastMaintenanceDate DATE,
    MeterStatus NVARCHAR(20) DEFAULT 'Active' CHECK (MeterStatus IN ('Active', 'Inactive', 'Faulty')),
    InitialReading DECIMAL(10,2) DEFAULT 0,
    FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID),
    FOREIGN KEY (UtilityTypeID) REFERENCES UtilityType(UtilityTypeID)
);

-- 5. METER READING TABLE
CREATE TABLE MeterReading (
    ReadingID INT PRIMARY KEY IDENTITY(1,1),
    MeterID INT NOT NULL,
    ReadingDate DATE NOT NULL,
    PreviousReading DECIMAL(10,2) NOT NULL,
    CurrentReading DECIMAL(10,2) NOT NULL,
    ConsumptionUnits AS (CurrentReading - PreviousReading) PERSISTED,
    ReadingMonth INT NOT NULL,
    ReadingYear INT NOT NULL,
    RecordedBy NVARCHAR(100),
    RecordedDate DATETIME DEFAULT GETDATE(),
    FOREIGN KEY (MeterID) REFERENCES Meter(MeterID),
    CONSTRAINT CHK_Reading CHECK (CurrentReading >= PreviousReading)
);

-- 6. BILL TABLE
CREATE TABLE Bill (
    BillID INT PRIMARY KEY IDENTITY(1,1),
    CustomerID INT NOT NULL,
    MeterID INT NOT NULL,
    ReadingID INT NOT NULL,
    BillingMonth INT NOT NULL,
    BillingYear INT NOT NULL,
    ConsumptionUnits DECIMAL(10,2) NOT NULL,
    RatePerUnit DECIMAL(10,2) NOT NULL,
    FixedCharges DECIMAL(10,2) DEFAULT 0,
    TotalAmount DECIMAL(10,2) NOT NULL,
    DueDate DATE NOT NULL,
    IssueDate DATETIME DEFAULT GETDATE(),
    Status NVARCHAR(20) DEFAULT 'Unpaid' CHECK (Status IN ('Paid', 'Unpaid', 'Overdue', 'Partial')),
    FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID),
    FOREIGN KEY (MeterID) REFERENCES Meter(MeterID),
    FOREIGN KEY (ReadingID) REFERENCES MeterReading(ReadingID)
);

-- 7. PAYMENT TABLE
CREATE TABLE Payment (
    PaymentID INT PRIMARY KEY IDENTITY(1,1),
    BillID INT NOT NULL,
    CustomerID INT NOT NULL,
    AmountPaid DECIMAL(10,2) NOT NULL,
    PaymentDate DATETIME DEFAULT GETDATE(),
    PaymentMethod NVARCHAR(50) NOT NULL CHECK (PaymentMethod IN ('Cash', 'Credit Card', 'Debit Card', 'Bank Transfer', 'Check', 'Online')),
    TransactionReference NVARCHAR(100),
    ProcessedBy NVARCHAR(100) NOT NULL,
    FOREIGN KEY (BillID) REFERENCES Bill(BillID),
    FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID)
);

-- 8. OUTSTANDING BALANCE TABLE
CREATE TABLE OutstandingBalance (
    BalanceID INT PRIMARY KEY IDENTITY(1,1),
    CustomerID INT NOT NULL UNIQUE,
    TotalOutstanding DECIMAL(10,2) DEFAULT 0,
    LastUpdated DATETIME DEFAULT GETDATE(),
    FOREIGN KEY (CustomerID) REFERENCES Customer(CustomerID)
);

-- 9. AUDIT LOG TABLE
CREATE TABLE AuditLog (
    LogID INT PRIMARY KEY IDENTITY(1,1),
    TableName NVARCHAR(50) NOT NULL,
    Operation NVARCHAR(20) NOT NULL,
    RecordID INT,
    OldValue NVARCHAR(MAX),
    NewValue NVARCHAR(MAX),
    ModifiedBy NVARCHAR(100),
    ModifiedDate DATETIME DEFAULT GETDATE()
);

-- ============================================
-- SAMPLE DATA INSERTION
-- ============================================

PRINT 'Inserting sample data...';

-- Insert Utility Types
INSERT INTO UtilityType (UtilityName, UnitOfMeasurement, Description) VALUES
('Electricity', 'kWh', 'Electric power supply'),
('Water', 'm�', 'Municipal water supply'),
('Gas', 'units', 'Natural gas supply');

-- Insert Tariff Plans
INSERT INTO TariffPlan (UtilityTypeID, PlanName, CustomerType, RatePerUnit, FixedCharge, EffectiveFromDate) VALUES
(1, 'Residential Electric Standard', 'Residential', 15.50, 100.00, '2024-01-01'),
(1, 'Commercial Electric Standard', 'Commercial', 18.75, 250.00, '2024-01-01'),
(1, 'Industrial Electric Standard', 'Industrial', 22.00, 500.00, '2024-01-01'),
(2, 'Residential Water Standard', 'Residential', 45.00, 50.00, '2024-01-01'),
(2, 'Commercial Water Standard', 'Commercial', 55.00, 150.00, '2024-01-01'),
(3, 'Residential Gas Standard', 'Residential', 35.00, 75.00, '2024-01-01'),
(3, 'Commercial Gas Standard', 'Commercial', 42.00, 200.00, '2024-01-01');

-- Insert Customers
INSERT INTO Customer (CustomerName, CustomerType, Address, Phone, Email) VALUES
('John Silva', 'Residential', '123 Galle Road, Colombo 03', '0771234567', 'john.silva@email.com'),
('Mary Fernando', 'Residential', '45 Kandy Road, Kandy', '0772345678', 'mary.fernando@email.com'),
('ABC Restaurant', 'Commercial', '78 Main Street, Negombo', '0773456789', 'info@abcrestaurant.lk'),
('Tech Solutions Pvt Ltd', 'Commercial', '12 Business Park, Malabe', '0774567890', 'contact@techsolutions.lk'),
('Green Textiles Ltd', 'Industrial', '34 Industrial Zone, Katunayake', '0775678901', 'admin@greentextiles.lk'),
('Peter Perera', 'Residential', '56 Temple Road, Nugegoda', '0776789012', 'peter.p@email.com'),
('Saman Traders', 'Commercial', '89 Market Street, Gampaha', '0777890123', 'saman.traders@email.com'),
('Nimal Jayasinghe', 'Residential', '23 Lake View, Mount Lavinia', '0778901234', 'nimal.j@email.com'),
('Star Manufacturing', 'Industrial', '67 Export Zone, Biyagama', '0779012345', 'info@starmanufacturing.lk'),
('Lakshmi Stores', 'Commercial', '90 High Level Road, Nugegoda', '0770123456', 'lakshmi.stores@email.com'),
('Kamal Rodrigo', 'Residential', '15 Sea View Road, Dehiwala', '0771234560', 'kamal.r@email.com'),
('Ravi Electronics', 'Commercial', '44 Shopping Complex, Maharagama', '0772345670', 'ravi.electronics@email.com');

-- Insert Meters
INSERT INTO Meter (CustomerID, UtilityTypeID, MeterNumber, InstallationDate, MeterStatus, InitialReading) VALUES
(1, 1, 'ELC-001-2024', '2024-01-15', 'Active', 1000.00),
(1, 2, 'WTR-001-2024', '2024-01-15', 'Active', 500.00),
(2, 1, 'ELC-002-2024', '2024-01-20', 'Active', 1500.00),
(3, 1, 'ELC-003-2024', '2024-02-01', 'Active', 2000.00),
(3, 2, 'WTR-002-2024', '2024-02-01', 'Active', 1000.00),
(3, 3, 'GAS-001-2024', '2024-02-01', 'Active', 300.00),
(4, 1, 'ELC-004-2024', '2024-02-10', 'Active', 5000.00),
(5, 1, 'ELC-005-2024', '2024-02-15', 'Active', 10000.00),
(5, 2, 'WTR-003-2024', '2024-02-15', 'Active', 2000.00),
(6, 1, 'ELC-006-2024', '2024-03-01', 'Active', 800.00),
(7, 1, 'ELC-007-2024', '2024-03-05', 'Active', 3000.00),
(8, 1, 'ELC-008-2024', '2024-03-10', 'Active', 1200.00),
(9, 1, 'ELC-009-2024', '2024-03-15', 'Active', 15000.00),
(10, 1, 'ELC-010-2024', '2024-03-20', 'Active', 2500.00);

-- Insert Meter Readings
INSERT INTO MeterReading (MeterID, ReadingDate, PreviousReading, CurrentReading, ReadingMonth, ReadingYear, RecordedBy) VALUES
(1, '2024-10-05', 1000.00, 1350.00, 10, 2024, 'Field Officer - Kasun'),
(2, '2024-10-05', 500.00, 580.00, 10, 2024, 'Field Officer - Kasun'),
(3, '2024-10-06', 1500.00, 1820.00, 10, 2024, 'Field Officer - Saman'),
(4, '2024-10-07', 2000.00, 2650.00, 10, 2024, 'Field Officer - Kasun'),
(5, '2024-10-07', 1000.00, 1150.00, 10, 2024, 'Field Officer - Kasun'),
(6, '2024-10-07', 300.00, 380.00, 10, 2024, 'Field Officer - Kasun'),
(7, '2024-10-08', 5000.00, 5850.00, 10, 2024, 'Field Officer - Saman'),
(8, '2024-10-09', 10000.00, 12500.00, 10, 2024, 'Field Officer - Nimal'),
(9, '2024-10-09', 2000.00, 2300.00, 10, 2024, 'Field Officer - Nimal'),
(10, '2024-10-10', 800.00, 1050.00, 10, 2024, 'Field Officer - Kasun'),
(11, '2024-10-11', 3000.00, 3720.00, 10, 2024, 'Field Officer - Saman'),
(12, '2024-10-12', 1200.00, 1480.00, 10, 2024, 'Field Officer - Kasun');

-- Insert Bills
INSERT INTO Bill (CustomerID, MeterID, ReadingID, BillingMonth, BillingYear, ConsumptionUnits, RatePerUnit, FixedCharges, TotalAmount, DueDate, Status) VALUES
(1, 1, 1, 10, 2024, 350.00, 15.50, 100.00, 5525.00, '2024-11-15', 'Unpaid'),
(1, 2, 2, 10, 2024, 80.00, 45.00, 50.00, 3650.00, '2024-11-15', 'Unpaid'),
(2, 3, 3, 10, 2024, 320.00, 15.50, 100.00, 5060.00, '2024-11-15', 'Unpaid'),
(3, 4, 4, 10, 2024, 650.00, 18.75, 250.00, 12437.50, '2024-11-15', 'Paid'),
(3, 5, 5, 10, 2024, 150.00, 55.00, 150.00, 8400.00, '2024-11-15', 'Paid'),
(3, 6, 6, 10, 2024, 80.00, 42.00, 200.00, 3560.00, '2024-11-15', 'Paid'),
(4, 7, 7, 10, 2024, 850.00, 18.75, 250.00, 16187.50, '2024-11-15', 'Unpaid'),
(5, 8, 8, 10, 2024, 2500.00, 22.00, 500.00, 55500.00, '2024-11-15', 'Overdue'),
(5, 9, 9, 10, 2024, 300.00, 55.00, 150.00, 16650.00, '2024-11-15', 'Overdue'),
(6, 10, 10, 10, 2024, 250.00, 15.50, 100.00, 3975.00, '2024-11-15', 'Unpaid'),
(7, 11, 11, 10, 2024, 720.00, 18.75, 250.00, 13750.00, '2024-11-15', 'Unpaid'),
(8, 12, 12, 10, 2024, 280.00, 15.50, 100.00, 4440.00, '2024-11-15', 'Paid');

-- Insert Payments
INSERT INTO Payment (BillID, CustomerID, AmountPaid, PaymentDate, PaymentMethod, TransactionReference, ProcessedBy) VALUES
(4, 3, 12437.50, '2024-11-10', 'Bank Transfer', 'TXN-2024-001', 'Cashier - Dilini'),
(5, 3, 8400.00, '2024-11-10', 'Bank Transfer', 'TXN-2024-002', 'Cashier - Dilini'),
(6, 3, 3560.00, '2024-11-10', 'Bank Transfer', 'TXN-2024-003', 'Cashier - Dilini'),
(12, 8, 4440.00, '2024-11-12', 'Cash', 'CASH-2024-001', 'Cashier - Priya');

-- Initialize Outstanding Balances
INSERT INTO OutstandingBalance (CustomerID, TotalOutstanding) 
SELECT CustomerID, 0 FROM Customer;

-- Update balances based on existing bills and payments
UPDATE OutstandingBalance
SET TotalOutstanding = (
    SELECT ISNULL(SUM(b.TotalAmount), 0) - ISNULL(SUM(p.AmountPaid), 0)
    FROM Bill b
    LEFT JOIN Payment p ON b.BillID = p.BillID
    WHERE b.CustomerID = OutstandingBalance.CustomerID
);

PRINT 'Sample data inserted successfully!';



PRINT 'Creating triggers...';

-- TRIGGER 1: Auto-update Outstanding Balance when Bill is created
GO
CREATE TRIGGER trg_UpdateBalanceOnBillCreation
ON Bill
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    
    UPDATE OutstandingBalance
    SET TotalOutstanding = TotalOutstanding + i.TotalAmount,
        LastUpdated = GETDATE()
    FROM OutstandingBalance ob
    INNER JOIN inserted i ON ob.CustomerID = i.CustomerID;
END;
GO

-- TRIGGER 2: Auto-update Outstanding Balance and Bill Status when Payment is made (FIXED)
GO
CREATE TRIGGER trg_UpdateBalanceOnPayment
ON Payment
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Update outstanding balance
    UPDATE OutstandingBalance
    SET TotalOutstanding = TotalOutstanding - i.AmountPaid,
        LastUpdated = GETDATE()
    FROM OutstandingBalance ob
    INNER JOIN inserted i ON ob.CustomerID = i.CustomerID;
    
    -- Update bill status based on total payments
    UPDATE b
    SET Status = CASE 
        WHEN TotalPaid >= b.TotalAmount THEN 'Paid'
        WHEN TotalPaid > 0 THEN 'Partial'
        ELSE 'Unpaid'
    END
    FROM Bill b
    INNER JOIN (
        SELECT p.BillID, SUM(p.AmountPaid) AS TotalPaid
        FROM Payment p
        INNER JOIN inserted i ON p.BillID = i.BillID
        GROUP BY p.BillID
    ) payments ON b.BillID = payments.BillID;
END;
GO

PRINT 'Triggers created successfully!';

PRINT 'Creating functions...';

-- FUNCTION 1: Calculate Monthly Bill for a Customer
GO
CREATE FUNCTION fn_CalculateMonthlyBill (
    @MeterID INT,
    @ConsumptionUnits DECIMAL(10,2)
)
RETURNS DECIMAL(10,2)
AS
BEGIN
    DECLARE @TotalBill DECIMAL(10,2);
    DECLARE @RatePerUnit DECIMAL(10,2);
    DECLARE @FixedCharge DECIMAL(10,2);
    
    SELECT TOP 1 @RatePerUnit = tp.RatePerUnit, 
                 @FixedCharge = tp.FixedCharge
    FROM Meter m
    INNER JOIN Customer c ON m.CustomerID = c.CustomerID
    INNER JOIN TariffPlan tp ON m.UtilityTypeID = tp.UtilityTypeID 
                            AND c.CustomerType = tp.CustomerType
    WHERE m.MeterID = @MeterID 
      AND tp.IsActive = 1
    ORDER BY tp.EffectiveFromDate DESC;
    
    SET @TotalBill = (@ConsumptionUnits * ISNULL(@RatePerUnit, 0)) + ISNULL(@FixedCharge, 0);
    
    RETURN @TotalBill;
END;
GO

-- FUNCTION 2: Calculate Late Payment Fee
GO
CREATE FUNCTION fn_CalculateLateFee (
    @BillID INT,
    @LateFeePercentage DECIMAL(5,2)
)
RETURNS DECIMAL(10,2)
AS
BEGIN
    DECLARE @LateFee DECIMAL(10,2);
    DECLARE @DaysOverdue INT;
    DECLARE @TotalAmount DECIMAL(10,2);
    
    SELECT @DaysOverdue = DATEDIFF(DAY, DueDate, GETDATE()),
           @TotalAmount = TotalAmount
    FROM Bill
    WHERE BillID = @BillID;
    
    IF @DaysOverdue > 0
        SET @LateFee = (@TotalAmount * @LateFeePercentage / 100);
    ELSE
        SET @LateFee = 0;
    
    RETURN ISNULL(@LateFee, 0);
END;
GO

PRINT 'Functions created successfully!';

PRINT 'Creating views...';

-- VIEW 1: Summary of Unpaid Bills with Customer Details
GO
CREATE VIEW vw_UnpaidBills AS
SELECT 
    b.BillID,
    c.CustomerID,
    c.CustomerName,
    c.CustomerType,
    c.Phone,
    ut.UtilityName,
    b.BillingMonth,
    b.BillingYear,
    b.ConsumptionUnits,
    b.TotalAmount,
    b.DueDate,
    DATEDIFF(DAY, b.DueDate, GETDATE()) AS DaysOverdue,
    b.Status
FROM Bill b
INNER JOIN Customer c ON b.CustomerID = c.CustomerID
INNER JOIN Meter m ON b.MeterID = m.MeterID
INNER JOIN UtilityType ut ON m.UtilityTypeID = ut.UtilityTypeID
WHERE b.Status IN ('Unpaid', 'Overdue', 'Partial');
GO

-- VIEW 2: Monthly Revenue Report
GO
CREATE VIEW vw_MonthlyRevenue AS
SELECT 
    MONTH(p.PaymentDate) AS PaymentMonth,
    YEAR(p.PaymentDate) AS PaymentYear,
    p.PaymentMethod,
    COUNT(p.PaymentID) AS TotalTransactions,
    SUM(p.AmountPaid) AS TotalRevenue
FROM Payment p
GROUP BY MONTH(p.PaymentDate), YEAR(p.PaymentDate), p.PaymentMethod;
GO

PRINT 'Views created successfully!';

PRINT 'Creating stored procedures...';

-- PROCEDURE 1: Generate Bill for a Customer based on Meter Reading
GO
CREATE PROCEDURE sp_GenerateBill
    @ReadingID INT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @MeterID INT, @CustomerID INT, @ConsumptionUnits DECIMAL(10,2);
    DECLARE @RatePerUnit DECIMAL(10,2), @FixedCharges DECIMAL(10,2);
    DECLARE @ReadingMonth INT, @ReadingYear INT;
    DECLARE @TotalAmount DECIMAL(10,2);
    
    -- Get reading details
    SELECT @MeterID = MeterID, 
           @ConsumptionUnits = ConsumptionUnits,
           @ReadingMonth = ReadingMonth,
           @ReadingYear = ReadingYear
    FROM MeterReading
    WHERE ReadingID = @ReadingID;
    
    -- Get customer and tariff details
    SELECT @CustomerID = m.CustomerID,
           @RatePerUnit = tp.RatePerUnit,
           @FixedCharges = tp.FixedCharge
    FROM Meter m
    INNER JOIN Customer c ON m.CustomerID = c.CustomerID
    INNER JOIN TariffPlan tp ON m.UtilityTypeID = tp.UtilityTypeID 
                            AND c.CustomerType = tp.CustomerType
    WHERE m.MeterID = @MeterID AND tp.IsActive = 1;
    
    -- Calculate total
    SET @TotalAmount = (@ConsumptionUnits * @RatePerUnit) + @FixedCharges;
    
    -- Insert bill
    INSERT INTO Bill (CustomerID, MeterID, ReadingID, BillingMonth, BillingYear, 
                      ConsumptionUnits, RatePerUnit, FixedCharges, TotalAmount, DueDate)
    VALUES (@CustomerID, @MeterID, @ReadingID, @ReadingMonth, @ReadingYear,
            @ConsumptionUnits, @RatePerUnit, @FixedCharges, @TotalAmount,
            DATEADD(DAY, 30, GETDATE()));
    
    SELECT 'Bill generated successfully' AS Message, SCOPE_IDENTITY() AS BillID;
END;
GO

-- PROCEDURE 2: Get Customer Bills with Payment History
GO
CREATE PROCEDURE sp_GetCustomerBills
    @CustomerID INT
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        b.BillID,
        b.BillingMonth,
        b.BillingYear,
        ut.UtilityName,
        b.ConsumptionUnits,
        b.TotalAmount,
        b.DueDate,
        b.Status,
        ISNULL(SUM(p.AmountPaid), 0) AS AmountPaid,
        b.TotalAmount - ISNULL(SUM(p.AmountPaid), 0) AS RemainingBalance
    FROM Bill b
    INNER JOIN Meter m ON b.MeterID = m.MeterID
    INNER JOIN UtilityType ut ON m.UtilityTypeID = ut.UtilityTypeID
    LEFT JOIN Payment p ON b.BillID = p.BillID
    WHERE b.CustomerID = @CustomerID
    GROUP BY b.BillID, b.BillingMonth, b.BillingYear, ut.UtilityName, 
             b.ConsumptionUnits, b.TotalAmount, b.DueDate, b.Status
    ORDER BY b.BillingYear DESC, b.BillingMonth DESC;
END;
GO

-- PROCEDURE 3: Get Defaulters List
GO
CREATE PROCEDURE sp_GetDefaulters
    @DaysOverdue INT = 30
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        c.CustomerID,
        c.CustomerName,
        c.Phone,
        c.Email,
        COUNT(b.BillID) AS OverdueBills,
        SUM(b.TotalAmount) AS TotalOverdueAmount,
        MAX(DATEDIFF(DAY, b.DueDate, GETDATE())) AS MaxDaysOverdue
    FROM Customer c
    INNER JOIN Bill b ON c.CustomerID = b.CustomerID
    WHERE b.Status IN ('Unpaid', 'Overdue')
      AND DATEDIFF(DAY, b.DueDate, GETDATE()) >= @DaysOverdue
    GROUP BY c.CustomerID, c.CustomerName, c.Phone, c.Email
    ORDER BY TotalOverdueAmount DESC;
END;
GO

-- PROCEDURE 4: Monthly Consumption Report
GO
CREATE PROCEDURE sp_MonthlyConsumptionReport
    @Month INT,
    @Year INT
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        c.CustomerID,
        c.CustomerName,
        c.CustomerType,
        ut.UtilityName,
        SUM(mr.ConsumptionUnits) AS TotalConsumption,
        COUNT(mr.ReadingID) AS NumberOfMeters,
        SUM(b.TotalAmount) AS TotalBillAmount
    FROM Customer c
    INNER JOIN Meter m ON c.CustomerID = m.CustomerID
    INNER JOIN UtilityType ut ON m.UtilityTypeID = ut.UtilityTypeID
    INNER JOIN MeterReading mr ON m.MeterID = mr.MeterID
    LEFT JOIN Bill b ON mr.ReadingID = b.ReadingID
    WHERE mr.ReadingMonth = @Month AND mr.ReadingYear = @Year
    GROUP BY c.CustomerID, c.CustomerName, c.CustomerType, ut.UtilityName
    ORDER BY TotalConsumption DESC;
END;
GO

PRINT 'Stored procedures created successfully!';

PRINT '';
PRINT '============================================';
PRINT 'DATABASE CREATION COMPLETED SUCCESSFULLY!';
PRINT '============================================';
PRINT '';

-- Display counts
PRINT 'Component Summary:';
PRINT '-------------------';
SELECT 'Tables' AS Component, COUNT(*) AS Count FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE'
UNION ALL
SELECT 'Triggers', COUNT(*) FROM sys.triggers WHERE parent_class = 1
UNION ALL
SELECT 'Functions', COUNT(*) FROM sys.objects WHERE type IN ('FN', 'IF', 'TF')
UNION ALL
SELECT 'Views', COUNT(*) FROM INFORMATION_SCHEMA.VIEWS
UNION ALL
SELECT 'Stored Procedures', COUNT(*) FROM sys.procedures;

PRINT '';
PRINT 'Sample Data Counts:';
PRINT '-------------------';
SELECT 'Customers' AS TableName, COUNT(*) AS RecordCount FROM Customer
UNION ALL
SELECT 'Utility Types', COUNT(*) FROM UtilityType
UNION ALL
SELECT 'Tariff Plans', COUNT(*) FROM TariffPlan
UNION ALL
SELECT 'Meters', COUNT(*) FROM Meter
UNION ALL
SELECT 'Meter Readings', COUNT(*) FROM MeterReading
UNION ALL
SELECT 'Bills', COUNT(*) FROM Bill
UNION ALL
SELECT 'Payments', COUNT(*) FROM Payment
UNION ALL
SELECT 'Outstanding Balances', COUNT(*) FROM OutstandingBalance;

PRINT '';
PRINT 'Database is ready to use!';
GO


SELECT name AS TriggerName, 
       OBJECT_NAME(parent_id) AS OnTable
FROM sys.triggers 
WHERE parent_class = 1;
INSERT INTO Payment (BillID, CustomerID, AmountPaid, PaymentDate, PaymentMethod, TransactionReference, ProcessedBy) VALUES
(7, 3, 12937.50, '2024-11-10', 'Bank Transfer', 'TXN-2024-004', 'Cashier - Dilini'),
(11, 9, 8000.00, '2024-11-10', 'Bank Transfer', 'TXN-2024-005', 'Cashier - Dilini'),
(1, 6, 3760.00, '2024-11-10', 'Bank Transfer', 'TXN-2024-006', 'Cashier - Priya'),
(2, 8, 4440.00, '2024-12-12', 'Cash', 'CASH-2024-002', 'Cashier - Priya'),
(10, 8, 11447.50, '2024-12-10', 'Bank Transfer', 'TXN-2024-007', 'Cashier - Dilini'),
(8, 5, 8790.00, '2024-12-11', 'Cash', 'CASH-2024-003', 'Cashier - Priya'),
(3, 5, 3670.00, '2024-12-12', 'Cash', 'CASH-2024-004', 'Cashier - Dilini'),
(9, 5, 5800.00, '2024-12-12', 'Cash', 'CASH-2024-005', 'Cashier - Priya');
INSERT INTO TariffPlan (UtilityTypeID, PlanName, CustomerType, RatePerUnit, FixedCharge, EffectiveFromDate) VALUES
(1, 'Industrial Electric Standard', 'Industrial', 16.40, 150.00, '2024-01-01'),
(2, 'Commercial Water Standard', 'Commercial', 14.65, 200.00, '2024-01-01'),
(3, 'Commercial Gas Standard', 'Commercial', 23.00, 550.00, '2024-01-01'),
(1, 'Residential Electric Standard', 'Residential', 85.00, 60.00, '2024-01-01'),
(1, 'Commercial Electric Standard', 'Commercial', 50.00, 150.00, '2024-01-01'),
(3, 'Industrial Gas Standard', 'Industrial', 32.00, 75.00, '2024-01-01'),
(2, 'Residential Water Standard', 'Residential', 45.00, 250.00, '2024-01-01');

SELECT dbo.fn_CalculateMonthlyBill(1, 350.00) AS BillCalculation;
SELECT dbo.fn_CalculateLateFee(1, 5.00) AS LateFee;
SELECT BillID, TotalAmount, 
       dbo.fn_CalculateLateFee(BillID, 2.5) AS LateFee
FROM Bill 
WHERE Status = 'Overdue';
SELECT * FROM vw_UnpaidBills ORDER BY DaysOverdue DESC;
SELECT * FROM vw_MonthlyRevenue ORDER BY PaymentYear DESC, PaymentMonth DESC;
EXEC sp_GenerateBill @ReadingID = 12;
EXEC sp_GetCustomerBills @CustomerID = 6;
EXEC sp_GetDefaulters @DaysOverdue = 10;
EXEC sp_MonthlyConsumptionReport @Month = 10, @Year = 2024;
UPDATE Bill SET DueDate = '2024-01-01' WHERE BillID = 1;
EXEC sp_GetDefaulters @DaysOverdue = 1;
INSERT INTO Bill (CustomerID, MeterID, ReadingID, BillingMonth, BillingYear, ConsumptionUnits, RatePerUnit, FixedCharges, TotalAmount, DueDate, Status) VALUES
(1, 1, 23, 9, 2025, 350.00, 15.50, 100.00, 5525.00, '2025-10-15', 'Unpaid'),
(1, 2, 24, 10, 2025, 80.00, 45.00, 50.00, 3650.00, '2025-11-13', 'Unpaid'),
(2, 3, 25, 10, 2025, 320.00, 15.50, 100.00, 5060.00, '2025-11-15', 'Unpaid');
INSERT INTO MeterReading (MeterID, ReadingDate, PreviousReading, CurrentReading, ReadingMonth, ReadingYear, RecordedBy) VALUES
(23, '2024-9-05', 1000.00, 1350.00, 10, 2024, 'Field Officer - Kasun'),
(24, '2024-10-05', 500.00, 580.00, 10, 2024, 'Field Officer - Kasun'),
(25, '2024-10-06', 1500.00, 1820.00, 10, 2024, 'Field Officer - Saman');
INSERT INTO Meter (CustomerID, UtilityTypeID, MeterNumber, InstallationDate, MeterStatus, InitialReading) VALUES
(1, 1, 'ELC-011-2024', '2024-01-15', 'Active', 1000.00),
(1, 2, 'WTR-004-2024', '2024-01-15', 'Active', 500.00),
(2, 1, 'ELC-012-2024', '2024-01-20', 'Active', 1500.00);
SELECT * FROM Meter
SELECT * FROM MeterReading