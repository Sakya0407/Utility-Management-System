const express = require('express');
const sql = require('mssql/msnodesqlv8');
const bodyParser = require('body-parser');
const cors = require('cors');

const app = express();

// Middleware
app.use(cors());
app.use(bodyParser.json());
app.use(express.static('public'));

// Database Configuration
const config = {
    connectionString: 'Driver={SQL Server};Server=.\\SQLEXPRESS;Database=UtilityManagementDB;Trusted_Connection=Yes;'
};

// ===== CONNECT TO DATABASE =====
let poolPromise;

async function connectDB() {
    try {
        poolPromise = await sql.connect(config);
        console.log('✓ Connected to SQL Server successfully!');
        return poolPromise;
    } catch (err) {
        console.error('✗ Database Connection Failed!');
        console.error('Error:', err.message);
        console.error('\nPlease check:');
        console.error('1. SQL Server is running');
        console.error('2. Database name is correct');
        console.error('3. Connection string is correct');
        process.exit(1);
    }
}

connectDB();

// ===== API ROUTES =====

// Test route
app.get('/', (req, res) => {
    res.send('Utility Management System Server is Running!');
});

// ========== CUSTOMER ROUTES ==========

// Get all customers
app.get('/api/customers', async (req, res) => {
    try {
        const pool = await poolPromise;
        const result = await pool.request()
            .query('SELECT * FROM Customer ORDER BY CustomerID DESC');
        res.json(result.recordset);
    } catch (err) {
        console.error('Error:', err);
        res.status(500).json({ error: err.message });
    }
});

// Get customer by ID
app.get('/api/customers/:id', async (req, res) => {
    try {
        const pool = await poolPromise;
        const result = await pool.request()
            .input('CustomerID', sql.Int, parseInt(req.params.id))
            .query('SELECT * FROM Customer WHERE CustomerID = @CustomerID');
        
        if (result.recordset.length === 0) {
            return res.status(404).json({ error: 'Customer not found' });
        }
        
        res.json(result.recordset[0]);
    } catch (err) {
        console.error('Error:', err);
        res.status(500).json({ error: err.message });
    }
});

// Add new customer
app.post('/api/customers', async (req, res) => {
    try {
        const { CustomerName, CustomerType, Address, Phone, Email } = req.body;
        const pool = await poolPromise;
        
        const result = await pool.request()
            .input('CustomerName', sql.NVarChar(100), CustomerName)
            .input('CustomerType', sql.NVarChar(50), CustomerType)
            .input('Address', sql.NVarChar(200), Address)
            .input('Phone', sql.NVarChar(15), Phone)
            .input('Email', sql.NVarChar(100), Email || null)
            .query(`INSERT INTO Customer (CustomerName, CustomerType, Address, Phone, Email) 
                    OUTPUT INSERTED.CustomerID
                    VALUES (@CustomerName, @CustomerType, @Address, @Phone, @Email)`);
        
        const customerID = result.recordset[0].CustomerID;
        
        // Initialize outstanding balance
        await pool.request()
            .input('CustomerID', sql.Int, customerID)
            .query('INSERT INTO OutstandingBalance (CustomerID, TotalOutstanding) VALUES (@CustomerID, 0)');
        
        res.json({ success: true, message: 'Customer added successfully', customerID });
    } catch (err) {
        console.error('Error:', err);
        res.status(500).json({ error: err.message });
    }
});

// ========== METER ROUTES ==========

// Get all meters
app.get('/api/meters', async (req, res) => {
    try {
        const pool = await poolPromise;
        const result = await pool.request().query(`
            SELECT m.*, c.CustomerName, ut.UtilityName
            FROM Meter m
            INNER JOIN Customer c ON m.CustomerID = c.CustomerID
            INNER JOIN UtilityType ut ON m.UtilityTypeID = ut.UtilityTypeID
            ORDER BY m.MeterID DESC
        `);
        res.json(result.recordset);
    } catch (err) {
        console.error('Error:', err);
        res.status(500).json({ error: err.message });
    }
});

// Get meters for dropdown (simplified)
app.get('/api/meters/simple', async (req, res) => {
    try {
        const pool = await poolPromise;
        const result = await pool.request().query(`
            SELECT m.MeterID, m.MeterNumber, c.CustomerName, ut.UtilityName,
                   m.InitialReading,
                   ISNULL((SELECT TOP 1 CurrentReading FROM MeterReading 
                           WHERE MeterID = m.MeterID 
                           ORDER BY ReadingDate DESC), m.InitialReading) as LastReading
            FROM Meter m
            INNER JOIN Customer c ON m.CustomerID = c.CustomerID
            INNER JOIN UtilityType ut ON m.UtilityTypeID = ut.UtilityTypeID
            WHERE m.MeterStatus = 'Active'
            ORDER BY m.MeterNumber
        `);
        res.json(result.recordset);
    } catch (err) {
        console.error('Error:', err);
        res.status(500).json({ error: err.message });
    }
});

// ========== METER READING ROUTES ==========

// Get all meter readings
app.get('/api/readings', async (req, res) => {
    try {
        const pool = await poolPromise;
        const result = await pool.request().query(`
            SELECT mr.*, m.MeterNumber, c.CustomerName, ut.UtilityName
            FROM MeterReading mr
            INNER JOIN Meter m ON mr.MeterID = m.MeterID
            INNER JOIN Customer c ON m.CustomerID = c.CustomerID
            INNER JOIN UtilityType ut ON m.UtilityTypeID = ut.UtilityTypeID
            ORDER BY mr.ReadingDate DESC, mr.ReadingID DESC
        `);
        res.json(result.recordset);
    } catch (err) {
        console.error('Error:', err);
        res.status(500).json({ error: err.message });
    }
});

// Add new meter reading and generate bill (FIXED)
app.post('/api/readings', async (req, res) => {
    try {
        console.log('Received reading data:', req.body);
        
        const { MeterID, ReadingDate, PreviousReading, CurrentReading, ReadingMonth, ReadingYear, RecordedBy } = req.body;
        
        // Convert and validate inputs
        const meterID = parseInt(MeterID);
        const prevReading = parseFloat(PreviousReading);
        const currReading = parseFloat(CurrentReading);
        const month = parseInt(ReadingMonth);
        const year = parseInt(ReadingYear);
        
        // Validate that current reading is greater than previous
        if (currReading < prevReading) {
            return res.status(400).json({ error: 'Current reading must be greater than or equal to previous reading' });
        }
        
        // Parse date properly
        const dateParts = ReadingDate.split('-');
        const readingDateObj = new Date(parseInt(dateParts[0]), parseInt(dateParts[1]) - 1, parseInt(dateParts[2]));
        
        const pool = await poolPromise;
        
        // Insert meter reading - get ID separately to avoid trigger issues
        await pool.request()
            .input('MeterID', sql.Int, meterID)
            .input('ReadingDate', sql.VarChar(10), ReadingDate)
            .input('PreviousReading', sql.Decimal(10, 2), prevReading)
            .input('CurrentReading', sql.Decimal(10, 2), currReading)
            .input('ReadingMonth', sql.Int, month)
            .input('ReadingYear', sql.Int, year)
            .input('RecordedBy', sql.NVarChar(100), RecordedBy)
            .query(`INSERT INTO MeterReading (MeterID, ReadingDate, PreviousReading, CurrentReading, ReadingMonth, ReadingYear, RecordedBy)
                    VALUES (@MeterID, @ReadingDate, @PreviousReading, @CurrentReading, @ReadingMonth, @ReadingYear, @RecordedBy)`);
        
        // Get the last inserted reading ID
        const readingResult = await pool.request()
            .query('SELECT TOP 1 ReadingID FROM MeterReading ORDER BY ReadingID DESC');
        
        const readingID = readingResult.recordset[0].ReadingID;
        console.log('Reading inserted with ID:', readingID);
        
        // Generate bill using stored procedure
        const billResult = await pool.request()
            .input('ReadingID', sql.Int, readingID)
            .execute('sp_GenerateBill');
        
        console.log('Bill generation result:', billResult.recordset);
        
        res.json({ 
            success: true, 
            message: 'Meter reading added and bill generated successfully', 
            readingID,
            billID: billResult.recordset[0].BillID
        });
    } catch (err) {
        console.error('Error in /api/readings:', err);
        res.status(500).json({ error: err.message });
    }
});

// ========== BILL ROUTES ==========

// Get all bills
app.get('/api/bills', async (req, res) => {
    try {
        const pool = await poolPromise;
        const result = await pool.request().query(`
            SELECT b.*, c.CustomerName, ut.UtilityName, m.MeterNumber
            FROM Bill b
            INNER JOIN Customer c ON b.CustomerID = c.CustomerID
            INNER JOIN Meter m ON b.MeterID = m.MeterID
            INNER JOIN UtilityType ut ON m.UtilityTypeID = ut.UtilityTypeID
            ORDER BY b.BillID DESC
        `);
        res.json(result.recordset);
    } catch (err) {
        console.error('Error:', err);
        res.status(500).json({ error: err.message });
    }
});

// Get unpaid bills
app.get('/api/bills/unpaid', async (req, res) => {
    try {
        const pool = await poolPromise;
        const result = await pool.request()
            .query('SELECT * FROM vw_UnpaidBills ORDER BY DaysOverdue DESC');
        res.json(result.recordset);
    } catch (err) {
        console.error('Error:', err);
        res.status(500).json({ error: err.message });
    }
});

// Get customer bills
app.get('/api/customers/:id/bills', async (req, res) => {
    try {
        const pool = await poolPromise;
        const result = await pool.request()
            .input('CustomerID', sql.Int, parseInt(req.params.id))
            .execute('sp_GetCustomerBills');
        res.json(result.recordset);
    } catch (err) {
        console.error('Error:', err);
        res.status(500).json({ error: err.message });
    }
});

// ========== PAYMENT ROUTES ==========

// Get all payments
app.get('/api/payments', async (req, res) => {
    try {
        const pool = await poolPromise;
        const result = await pool.request().query(`
            SELECT p.*, c.CustomerName, b.BillingMonth, b.BillingYear
            FROM Payment p
            INNER JOIN Customer c ON p.CustomerID = c.CustomerID
            INNER JOIN Bill b ON p.BillID = b.BillID
            ORDER BY p.PaymentDate DESC
        `);
        res.json(result.recordset);
    } catch (err) {
        console.error('Error:', err);
        res.status(500).json({ error: err.message });
    }
});

// Add payment (FIXED - Avoiding OUTPUT with Triggers)
app.post('/api/payments', async (req, res) => {
    try {
        console.log('Received payment data:', req.body);
        
        const { BillID, CustomerID, AmountPaid, PaymentMethod, TransactionReference, ProcessedBy } = req.body;
        
        // Convert and validate inputs
        const billID = parseInt(BillID);
        const customerID = parseInt(CustomerID);
        const amount = parseFloat(AmountPaid);
        
        if (isNaN(billID) || isNaN(customerID) || isNaN(amount)) {
            return res.status(400).json({ error: 'Invalid input: Bill ID, Customer ID, and Amount must be valid numbers' });
        }
        
        const pool = await poolPromise;
        
        // Check if bill exists
        const billCheck = await pool.request()
            .input('BillID', sql.Int, billID)
            .query('SELECT TotalAmount, Status FROM Bill WHERE BillID = @BillID');
        
        if (billCheck.recordset.length === 0) {
            return res.status(404).json({ error: 'Bill not found' });
        }
        
        // Insert payment without OUTPUT clause (to avoid trigger conflict)
        await pool.request()
            .input('BillID', sql.Int, billID)
            .input('CustomerID', sql.Int, customerID)
            .input('AmountPaid', sql.Decimal(10, 2), amount)
            .input('PaymentMethod', sql.NVarChar(50), PaymentMethod)
            .input('TransactionReference', sql.NVarChar(100), TransactionReference || null)
            .input('ProcessedBy', sql.NVarChar(100), ProcessedBy)
            .query(`INSERT INTO Payment (BillID, CustomerID, AmountPaid, PaymentMethod, TransactionReference, ProcessedBy)
                    VALUES (@BillID, @CustomerID, @AmountPaid, @PaymentMethod, @TransactionReference, @ProcessedBy)`);
        
        // Get the last inserted payment ID
        const paymentResult = await pool.request()
            .query('SELECT TOP 1 PaymentID FROM Payment ORDER BY PaymentID DESC');
        
        const paymentID = paymentResult.recordset[0].PaymentID;
        console.log('Payment inserted successfully with ID:', paymentID);
        
        res.json({ 
            success: true, 
            message: 'Payment recorded successfully', 
            paymentID
        });
    } catch (err) {
        console.error('Error in /api/payments:', err);
        res.status(500).json({ error: err.message });
    }
});

// ========== UTILITY ROUTES ==========

// Get utility types
app.get('/api/utilities', async (req, res) => {
    try {
        const pool = await poolPromise;
        const result = await pool.request()
            .query('SELECT * FROM UtilityType');
        res.json(result.recordset);
    } catch (err) {
        console.error('Error:', err);
        res.status(500).json({ error: err.message });
    }
});

// ========== DASHBOARD ROUTES ==========

// Get dashboard stats
app.get('/api/dashboard/stats', async (req, res) => {
    try {
        const pool = await poolPromise;
        
        const totalCustomers = await pool.request()
            .query('SELECT COUNT(*) as count FROM Customer WHERE Status = \'Active\'');
        
        const totalRevenue = await pool.request()
            .query('SELECT ISNULL(SUM(AmountPaid), 0) as total FROM Payment WHERE MONTH(PaymentDate) = MONTH(GETDATE()) AND YEAR(PaymentDate) = YEAR(GETDATE())');
        
        const unpaidBills = await pool.request()
            .query('SELECT COUNT(*) as count FROM Bill WHERE Status IN (\'Unpaid\', \'Overdue\')');
        
        const totalMeters = await pool.request()
            .query('SELECT COUNT(*) as count FROM Meter WHERE MeterStatus = \'Active\'');
        
        res.json({
            totalCustomers: totalCustomers.recordset[0].count,
            monthlyRevenue: totalRevenue.recordset[0].total,
            unpaidBills: unpaidBills.recordset[0].count,
            totalMeters: totalMeters.recordset[0].count
        });
    } catch (err) {
        console.error('Error:', err);
        res.status(500).json({ error: err.message });
    }
});

// ========== REPORT ROUTES ==========

// Get defaulters report
app.get('/api/reports/defaulters', async (req, res) => {
    try {
        const daysOverdue = parseInt(req.query.days) || 30;
        const pool = await poolPromise;
        
        const result = await pool.request()
            .input('DaysOverdue', sql.Int, daysOverdue)
            .execute('sp_GetDefaulters');
        
        res.json(result.recordset);
    } catch (err) {
        console.error('Error:', err);
        res.status(500).json({ error: err.message });
    }
});

// Get monthly consumption report
app.get('/api/reports/consumption', async (req, res) => {
    try {
        const month = parseInt(req.query.month) || new Date().getMonth() + 1;
        const year = parseInt(req.query.year) || new Date().getFullYear();
        const pool = await poolPromise;
        
        const result = await pool.request()
            .input('Month', sql.Int, month)
            .input('Year', sql.Int, year)
            .execute('sp_MonthlyConsumptionReport');
        
        res.json(result.recordset);
    } catch (err) {
        console.error('Error:', err);
        res.status(500).json({ error: err.message });
    }
});

// Get monthly revenue report
app.get('/api/reports/revenue', async (req, res) => {
    try {
        const pool = await poolPromise;
        const result = await pool.request()
            .query('SELECT * FROM vw_MonthlyRevenue ORDER BY PaymentYear DESC, PaymentMonth DESC');
        res.json(result.recordset);
    } catch (err) {
        console.error('Error:', err);
        res.status(500).json({ error: err.message });
    }
});

// ========== OUTSTANDING BALANCE ROUTES ==========

// Get outstanding balances
app.get('/api/balances', async (req, res) => {
    try {
        const pool = await poolPromise;
        const result = await pool.request().query(`
            SELECT ob.*, c.CustomerName, c.Phone, c.Email
            FROM OutstandingBalance ob
            INNER JOIN Customer c ON ob.CustomerID = c.CustomerID
            WHERE ob.TotalOutstanding > 0
            ORDER BY ob.TotalOutstanding DESC
        `);
        res.json(result.recordset);
    } catch (err) {
        console.error('Error:', err);
        res.status(500).json({ error: err.message });
    }
});

// ===== START SERVER =====
const PORT = 3000;

app.listen(PORT, () => {
    console.log('\n╔════════════════════════════════════════════════╗');
    console.log('║   Utility Management System Server Started    ║');
    console.log('╠════════════════════════════════════════════════╣');
    console.log(`║   Server: http://localhost:${PORT}              ║`);
    console.log('║   Status: ✓ Running                            ║');
    console.log('╚════════════════════════════════════════════════╝\n');
});

// Handle shutdown
process.on('SIGINT', async () => {
    console.log('\nShutting down server...');
    await sql.close();
    process.exit(0);
});