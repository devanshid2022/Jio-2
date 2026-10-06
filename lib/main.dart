import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: SimSalesHomePage(),
  ));
}

class SimSalesHomePage extends StatefulWidget {
  const SimSalesHomePage({super.key});

  @override
  State<SimSalesHomePage> createState() => _SimSalesHomePageState();
}

class _SimSalesHomePageState extends State<SimSalesHomePage> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _dobController = TextEditingController();
  final _idNumberController = TextEditingController();
  final _iccidController = TextEditingController();
  final _dateController = TextEditingController(
    text: DateFormat('dd/MM/yyyy').format(DateTime.now()),
  );

  String _selectedCompany = 'Jio';
  String _selectedProduct = 'New SIM';
  final List<String> _companies = ['Jio', 'Airtel', 'Vi', 'BSNL'];
  final List<String> _products = ['New SIM', 'MNP', 'SIM Swap', 'Postpaid'];

  List<Map<String, String>> _savedRecords = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedRecords();
  }

  // ૧. મોબાઈલ મેમરીમાંથી કાયમી સેવ થયેલો ડેટા લોડ કરવો
  Future<void> _loadSavedRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString('saved_sim_sales_data');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        setState(() {
          _savedRecords = decoded.map((e) => Map<String, String>.from(e)).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading records: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // ૨. મોબાઈલમાં ડેટા કાયમ માટે સેવ કરવો (Local Database)
  Future<void> _persistRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_sim_sales_data', jsonEncode(_savedRecords));

      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/sim_sales_backup.csv');
      final buffer = StringBuffer();
      buffer.writeln('Company,Product,ICCID,Name,Phone,ID_Number,DOB,Date,Address');
      for (final r in _savedRecords) {
        buffer.writeln(
          '"${r['Company']}","${r['Product']}","${r['ICCID']}","${r['Name']}","${r['Phone']}","${r['ID_Number']}","${r['DOB']}","${r['Date']}","${r['Address']}"',
        );
      }
      await file.writeAsString(buffer.toString());
    } catch (e) {
      debugPrint('Error saving records: $e');
    }
  }

  // ૩. ક્રેશ ન થાય તેવું સુરક્ષિત કેમેરા સ્કેનર
  Future<void> _openSafeScanner({required bool isSimScan}) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (ctx) => SafeScannerScreen(
          title: isSimScan ? 'SIM Card Barcode Scan' : 'Aadhaar / ID Scan',
          hintText: isSimScan
              ? 'SIM પેકેટ પરનો બારકોડ સામે રાખો'
              : 'આધાર QR કોડ અથવા ID સામે રાખો',
        ),
      ),
    );

    if (result != null && result.isNotEmpty) {
      if (isSimScan) {
        _processSimBarcode(result);
      } else {
        _processAadhaarData(result);
      }
    }
  }

  void _processSimBarcode(String value) {
    final regExp = RegExp(r'\b(89\d{16,20}|\d{18,22})\b');
    final match = regExp.firstMatch(value);
    final iccid = match != null ? match.group(0)! : value.trim();

    setState(() {
      _iccidController.text = iccid;
    });
    _showSnackBar('SIM ICCID સ્કેન સફળ: $iccid');
  }

  void _processAadhaarData(String rawText) {
    final aadhaarMatch = RegExp(r'\b\d{4}\s?\d{4}\s?\d{4}\b').firstMatch(rawText);
    if (aadhaarMatch != null) {
      _idNumberController.text = aadhaarMatch.group(0)!;
    }

    final panMatch = RegExp(r'[A-Z]{5}[0-9]{4}[A-Z]{1}').firstMatch(rawText.toUpperCase());
    if (panMatch != null) {
      _idNumberController.text = panMatch.group(0)!;
    }

    final dobMatch = RegExp(r'(\d{2}[\/\-]\d{2}[\/\-]\d{4}|\d{4}[\/\-]\d{2}[\/\-]\d{2})').firstMatch(rawText);
    if (dobMatch != null) {
      _dobController.text = dobMatch.group(0)!;
    }

    final nameMatch = RegExp(r'name="([^"]+)"', caseSensitive: false).firstMatch(rawText);
    if (nameMatch != null) {
      _nameController.text = nameMatch.group(1)!;
    }

    _showSnackBar('વિગતો આપોઆપ ભરાઈ ગઈ!');
  }

  // ૪. ડેટા સેવ કરવો (કાયમી)
  void _saveRecord() async {
    if (_nameController.text.trim().isEmpty && _iccidController.text.trim().isEmpty) {
      _showSnackBar('કૃપા કરીને નામ અથવા ICCID નંબર દાખલ કરો.');
      return;
    }

    final record = {
      'Name': _nameController.text.trim(),
      'Phone': _phoneController.text.trim(),
      'Address': _addressController.text.trim(),
      'DOB': _dobController.text.trim(),
      'ID_Number': _idNumberController.text.trim(),
      'ICCID': _iccidController.text.trim(),
      'Product': _selectedProduct,
      'Company': _selectedCompany,
      'Date': _dateController.text.trim(),
      'Timestamp': DateTime.now().toIso8601String(),
    };

    setState(() {
      _savedRecords.insert(0, record);
    });

    await _persistRecords();
    _clearForm();
    _showSnackBar('ગ્રાહકનો ડેટા કાયમ માટે સેવ થઈ ગયો! ✅');
  }

  void _clearForm() {
    _nameController.clear();
    _phoneController.clear();
    _addressController.clear();
    _dobController.clear();
    _idNumberController.clear();
    _iccidController.clear();
  }

  // ૫. બેકઅપ ફાઇલ અને WhatsApp / Drive / Downloads શેરિંગ
  Future<void> _exportBackupFile() async {
    if (_savedRecords.isEmpty) {
      _showSnackBar('બેકઅપ માટે કોઈ ડેટા નથી.');
      return;
    }

    try {
      final buffer = StringBuffer();
      buffer.writeln('Company,Product,ICCID,Name,Phone,ID_Number,DOB,Date,Address');
      for (final r in _savedRecords) {
        buffer.writeln(
          '"${r['Company']}","${r['Product']}","${r['ICCID']}","${r['Name']}","${r['Phone']}","${r['ID_Number']}","${r['DOB']}","${r['Date']}","${r['Address']}"',
        );
      }

      final directory = await getApplicationDocumentsDirectory();
      final nowStr = DateFormat('dd_MM_yyyy_HHmm').format(DateTime.now());
      final file = File('${directory.path}/SIM_Sales_Backup_$nowStr.csv');
      await file.writeAsString(buffer.toString());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'SIM Sales Backup Report (${_savedRecords.length} Customers) - $nowStr',
      );
      _showSnackBar('બેકઅપ ફાઇલ તૈયાર!');
    } catch (e) {
      _showSnackBar('બેકઅપ એરર: $e');
    }
  }

  void _deleteRecord(int index) async {
    setState(() {
      _savedRecords.removeAt(index);
    });
    await _persistRecords();
    _showSnackBar('રેકોર્ડ ડિલીટ થઈ ગયો.');
  }

  void _showSavedListBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          builder: (_, scrollController) {
            return Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  height: 4,
                  width: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'સેવ કરેલા ગ્રાહકો (${_savedRecords.length})',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _exportBackupFile();
                        },
                        icon: const Icon(Icons.share, size: 18),
                        label: const Text('Export Excel'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: _savedRecords.isEmpty
                      ? const Center(child: Text('હજુ સુધી કોઈ રેકોર્ડ સેવ કરેલ નથી.'))
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: _savedRecords.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, index) {
                            final r = _savedRecords[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _getCompanyColor(r['Company'] ?? ''),
                                foregroundColor: Colors.white,
                                child: Text(r['Company']?[0] ?? 'S'),
                              ),
                              title: Text(
                                r['Name']?.isNotEmpty == true ? r['Name']! : 'અજાણ્યો ગ્રાહક',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                '📞 ${r['Phone'] ?? '-'} | 📶 ${r['ICCID'] ?? '-'}\n📅 ${r['Date'] ?? '-'} (${r['Product'] ?? '-'})',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () {
                                  _deleteRecord(index);
                                  Navigator.pop(ctx);
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Color _getCompanyColor(String company) {
    switch (company.toLowerCase()) {
      case 'jio':
        return Colors.blue.shade900;
      case 'airtel':
        return Colors.red.shade700;
      case 'vi':
        return Colors.orange.shade800;
      case 'bsnl':
        return Colors.blue.shade700;
      default:
        return Colors.teal;
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('📱 SIM Sales Scan App'),
        backgroundColor: Colors.teal.shade700,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Saved Records',
            onPressed: _showSavedListBottomSheet,
          ),
          IconButton(
            icon: const Icon(Icons.backup),
            tooltip: 'Export Backup',
            onPressed: _exportBackupFile,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // સ્કેન બટનો
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    const Text('📷 કેમેરા સ્કેનર (Camera Scanner)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _openSafeScanner(isSimScan: true),
                            icon: const Icon(Icons.sim_card),
                            label: const Text('SIM Barcode'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade800,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _openSafeScanner(isSimScan: false),
                            icon: const Icon(Icons.qr_code_scanner),
                            label: const Text('Aadhaar / ID'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // કંપની અને પ્રોડક્ટ સિલેક્શન
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedCompany,
                    decoration: const InputDecoration(labelText: 'કંપની', border: OutlineInputBorder()),
                    items: _companies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (val) => setState(() => _selectedCompany = val!),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedProduct,
                    decoration: const InputDecoration(labelText: 'પ્રોડક્ટ', border: OutlineInputBorder()),
                    items: _products.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                    onChanged: (val) => setState(() => _selectedProduct = val!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ફોર્મ ઇનપુટ્સ
            TextField(
              controller: _iccidController,
              decoration: const InputDecoration(
                labelText: 'ICCID / SIM નંબર (18-22 અંક)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.numbers),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'ગ્રાહકનું નામ (Customer Name)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'મોબાઇલ નંબર',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _idNumberController,
              decoration: const InputDecoration(
                labelText: 'Aadhaar / PAN નંબર',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.badge),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dobController,
                    decoration: const InputDecoration(
                      labelText: 'જન્મ તારીખ (DOB)',
                      border: OutlineInputBorder(),
                      hintText: 'DD/MM/YYYY',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _dateController,
                    decoration: const InputDecoration(
                      labelText: 'વેચાણ તારીખ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _addressController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'સરનામું (Address)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.home),
              ),
            ),
            const SizedBox(height: 14),

            // સેવ બટન
            ElevatedButton.icon(
              onPressed: _saveRecord,
              icon: const Icon(Icons.save),
              label: const Text('ગ્રાહકનો ડેટા સેવ કરો (Permanent Save)', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),

            // સેવ થયેલા રેકોર્ડ્સ બટન
            OutlinedButton.icon(
              onPressed: _showSavedListBottomSheet,
              icon: const Icon(Icons.list_alt),
              label: Text('સેવ કરેલા ગ્રાહકો જુઓ (${_savedRecords.length})'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),

            const SizedBox(height: 20),

            // બનાવનારની વિગત (Developer Contact Info)
            Card(
              elevation: 1,
              color: Colors.teal.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                child: Column(
                  children: [
                    const Text(
                      '🛠️ Application Developed By',
                      style: TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Dilipsinh Parmar',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.phone, size: 16, color: Colors.teal),
                        SizedBox(width: 6),
                        Text(
                          'Contact: +91 9574932281',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.teal),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ક્રેશ-ફ્રી સુરક્ષિત સ્કેનર સ્ક્રીન
class SafeScannerScreen extends StatefulWidget {
  final String title;
  final String hintText;
  const SafeScannerScreen({super.key, required this.title, required this.hintText});

  @override
  State<SafeScannerScreen> createState() => _SafeScannerScreenState();
}

class _SafeScannerScreenState extends State<SafeScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    returnImage: false,
  );
  bool _hasCaptured = false;
  final _manualController = TextEditingController();

  @override
  void dispose() {
    _scannerController.dispose();
    _manualController.dispose();
    super.dispose();
  }

  void _handleBarcode(BarcodeCapture capture) {
    if (_hasCaptured) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue != null && barcode!.rawValue!.isNotEmpty) {
      _hasCaptured = true;
      _scannerController.stop();
      Navigator.of(context).pop(barcode.rawValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.teal.shade800,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _scannerController.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _scannerController.switchCamera(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: _handleBarcode,
                  errorBuilder: (ctx, error) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          'કેમેરા ચાલુ થવામાં તકલીફ આવી.\nકૃપા કરીને નીચે મેન્યુઅલ નંબર દાખલ કરો.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    );
                  },
                ),
                Center(
                  child: Container(
                    width: 280,
                    height: 180,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.greenAccent, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      widget.hintText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12.0),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualController,
                    decoration: const InputDecoration(
                      hintText: 'અથવા અહીં જાતે નંબર લખો',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    if (_manualController.text.trim().isNotEmpty) {
                      _scannerController.stop();
                      Navigator.of(context).pop(_manualController.text.trim());
                    }
                  },
                  child: const Text('OK'),
                ),
              ],
            ),import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: SimSalesHomePage(),
  ));
}

class SimSalesHomePage extends StatefulWidget {
  const SimSalesHomePage({super.key});

  @override
  State<SimSalesHomePage> createState() => _SimSalesHomePageState();
}

class _SimSalesHomePageState extends State<SimSalesHomePage> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _dobController = TextEditingController();
  final _idNumberController = TextEditingController();
  final _iccidController = TextEditingController();
  final _dateController = TextEditingController(
    text: DateFormat('dd/MM/yyyy').format(DateTime.now()),
  );

  String _selectedCompany = 'Jio';
  String _selectedProduct = 'New SIM';
  final List<String> _companies = ['Jio', 'Airtel', 'Vi', 'BSNL'];
  final List<String> _products = ['New SIM', 'MNP', 'SIM Swap', 'Postpaid'];

  List<Map<String, String>> _savedRecords = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedRecords();
  }

  // ૧. મોબાઈલ મેમરીમાંથી કાયમી સેવ થયેલો ડેટા લોડ કરવો
  Future<void> _loadSavedRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString('saved_sim_sales_data');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        setState(() {
          _savedRecords = decoded.map((e) => Map<String, String>.from(e)).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading records: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // ૨. મોબાઈલમાં ડેટા કાયમ માટે સેવ કરવો (Local Database)
  Future<void> _persistRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_sim_sales_data', jsonEncode(_savedRecords));

      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/sim_sales_backup.csv');
      final buffer = StringBuffer();
      buffer.writeln('Company,Product,ICCID,Name,Phone,ID_Number,DOB,Date,Address');
      for (final r in _savedRecords) {
        buffer.writeln(
          '"${r['Company']}","${r['Product']}","${r['ICCID']}","${r['Name']}","${r['Phone']}","${r['ID_Number']}","${r['DOB']}","${r['Date']}","${r['Address']}"',
        );
      }
      await file.writeAsString(buffer.toString());
    } catch (e) {
      debugPrint('Error saving records: $e');
    }
  }

  // ૩. ક્રેશ ન થાય તેવું સુરક્ષિત કેમેરા સ્કેનર
  Future<void> _openSafeScanner({required bool isSimScan}) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (ctx) => SafeScannerScreen(
          title: isSimScan ? 'SIM Card Barcode Scan' : 'Aadhaar / ID Scan',
          hintText: isSimScan
              ? 'SIM પેકેટ પરનો બારકોડ સામે રાખો'
              : 'આધાર QR કોડ અથવા ID સામે રાખો',
        ),
      ),
    );

    if (result != null && result.isNotEmpty) {
      if (isSimScan) {
        _processSimBarcode(result);
      } else {
        _processAadhaarData(result);
      }
    }
  }

  void _processSimBarcode(String value) {
    final regExp = RegExp(r'\b(89\d{16,20}|\d{18,22})\b');
    final match = regExp.firstMatch(value);
    final iccid = match != null ? match.group(0)! : value.trim();

    setState(() {
      _iccidController.text = iccid;
    });
    _showSnackBar('SIM ICCID સ્કેન સફળ: $iccid');
  }

  void _processAadhaarData(String rawText) {
    final aadhaarMatch = RegExp(r'\b\d{4}\s?\d{4}\s?\d{4}\b').firstMatch(rawText);
    if (aadhaarMatch != null) {
      _idNumberController.text = aadhaarMatch.group(0)!;
    }

    final panMatch = RegExp(r'[A-Z]{5}[0-9]{4}[A-Z]{1}').firstMatch(rawText.toUpperCase());
    if (panMatch != null) {
      _idNumberController.text = panMatch.group(0)!;
    }

    final dobMatch = RegExp(r'(\d{2}[\/\-]\d{2}[\/\-]\d{4}|\d{4}[\/\-]\d{2}[\/\-]\d{2})').firstMatch(rawText);
    if (dobMatch != null) {
      _dobController.text = dobMatch.group(0)!;
    }

    final nameMatch = RegExp(r'name="([^"]+)"', caseSensitive: false).firstMatch(rawText);
    if (nameMatch != null) {
      _nameController.text = nameMatch.group(1)!;
    }

    _showSnackBar('વિગતો આપોઆપ ભરાઈ ગઈ!');
  }

  // ૪. ડેટા સેવ કરવો (કાયમી)
  void _saveRecord() async {
    if (_nameController.text.trim().isEmpty && _iccidController.text.trim().isEmpty) {
      _showSnackBar('કૃપા કરીને નામ અથવા ICCID નંબર દાખલ કરો.');
      return;
    }

    final record = {
      'Name': _nameController.text.trim(),
      'Phone': _phoneController.text.trim(),
      'Address': _addressController.text.trim(),
      'DOB': _dobController.text.trim(),
      'ID_Number': _idNumberController.text.trim(),
      'ICCID': _iccidController.text.trim(),
      'Product': _selectedProduct,
      'Company': _selectedCompany,
      'Date': _dateController.text.trim(),
      'Timestamp': DateTime.now().toIso8601String(),
    };

    setState(() {
      _savedRecords.insert(0, record);
    });

    await _persistRecords();
    _clearForm();
    _showSnackBar('ગ્રાહકનો ડેટા કાયમ માટે સેવ થઈ ગયો! ✅');
  }

  void _clearForm() {
    _nameController.clear();
    _phoneController.clear();
    _addressController.clear();
    _dobController.clear();
    _idNumberController.clear();
    _iccidController.clear();
  }

  // ૫. બેકઅપ ફાઇલ અને WhatsApp / Drive / Downloads શેરિંગ
  Future<void> _exportBackupFile() async {
    if (_savedRecords.isEmpty) {
      _showSnackBar('બેકઅપ માટે કોઈ ડેટા નથી.');
      return;
    }

    try {
      final buffer = StringBuffer();
      buffer.writeln('Company,Product,ICCID,Name,Phone,ID_Number,DOB,Date,Address');
      for (final r in _savedRecords) {
        buffer.writeln(
          '"${r['Company']}","${r['Product']}","${r['ICCID']}","${r['Name']}","${r['Phone']}","${r['ID_Number']}","${r['DOB']}","${r['Date']}","${r['Address']}"',
        );
      }

      final directory = await getApplicationDocumentsDirectory();
      final nowStr = DateFormat('dd_MM_yyyy_HHmm').format(DateTime.now());
      final file = File('${directory.path}/SIM_Sales_Backup_$nowStr.csv');
      await file.writeAsString(buffer.toString());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'SIM Sales Backup Report (${_savedRecords.length} Customers) - $nowStr',
      );
      _showSnackBar('બેકઅપ ફાઇલ તૈયાર!');
    } catch (e) {
      _showSnackBar('બેકઅપ એરર: $e');
    }
  }

  void _deleteRecord(int index) async {
    setState(() {
      _savedRecords.removeAt(index);
    });
    await _persistRecords();
    _showSnackBar('રેકોર્ડ ડિલીટ થઈ ગયો.');
  }

  void _showSavedListBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          builder: (_, scrollController) {
            return Column(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  height: 4,
                  width: 40,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'સેવ કરેલા ગ્રાહકો (${_savedRecords.length})',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _exportBackupFile();
                        },
                        icon: const Icon(Icons.share, size: 18),
                        label: const Text('Export Excel'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: _savedRecords.isEmpty
                      ? const Center(child: Text('હજુ સુધી કોઈ રેકોર્ડ સેવ કરેલ નથી.'))
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: _savedRecords.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, index) {
                            final r = _savedRecords[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: _getCompanyColor(r['Company'] ?? ''),
                                foregroundColor: Colors.white,
                                child: Text(r['Company']?[0] ?? 'S'),
                              ),
                              title: Text(
                                r['Name']?.isNotEmpty == true ? r['Name']! : 'અજાણ્યો ગ્રાહક',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                '📞 ${r['Phone'] ?? '-'} | 📶 ${r['ICCID'] ?? '-'}\n📅 ${r['Date'] ?? '-'} (${r['Product'] ?? '-'})',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () {
                                  _deleteRecord(index);
                                  Navigator.pop(ctx);
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Color _getCompanyColor(String company) {
    switch (company.toLowerCase()) {
      case 'jio':
        return Colors.blue.shade900;
      case 'airtel':
        return Colors.red.shade700;
      case 'vi':
        return Colors.orange.shade800;
      case 'bsnl':
        return Colors.blue.shade700;
      default:
        return Colors.teal;
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('📱 SIM Sales Scan App'),
        backgroundColor: Colors.teal.shade700,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Saved Records',
            onPressed: _showSavedListBottomSheet,
          ),
          IconButton(
            icon: const Icon(Icons.backup),
            tooltip: 'Export Backup',
            onPressed: _exportBackupFile,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // સ્કેન બટનો
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    const Text('📷 કેમેરા સ્કેનર (Camera Scanner)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _openSafeScanner(isSimScan: true),
                            icon: const Icon(Icons.sim_card),
                            label: const Text('SIM Barcode'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade800,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _openSafeScanner(isSimScan: false),
                            icon: const Icon(Icons.qr_code_scanner),
                            label: const Text('Aadhaar / ID'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // કંપની અને પ્રોડક્ટ સિલેક્શન
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedCompany,
                    decoration: const InputDecoration(labelText: 'કંપની', border: OutlineInputBorder()),
                    items: _companies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                    onChanged: (val) => setState(() => _selectedCompany = val!),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedProduct,
                    decoration: const InputDecoration(labelText: 'પ્રોડક્ટ', border: OutlineInputBorder()),
                    items: _products.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                    onChanged: (val) => setState(() => _selectedProduct = val!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ફોર્મ ઇનપુટ્સ
            TextField(
              controller: _iccidController,
              decoration: const InputDecoration(
                labelText: 'ICCID / SIM નંબર (18-22 અંક)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.numbers),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'ગ્રાહકનું નામ (Customer Name)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'મોબાઇલ નંબર',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _idNumberController,
              decoration: const InputDecoration(
                labelText: 'Aadhaar / PAN નંબર',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.badge),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dobController,
                    decoration: const InputDecoration(
                      labelText: 'જન્મ તારીખ (DOB)',
                      border: OutlineInputBorder(),
                      hintText: 'DD/MM/YYYY',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _dateController,
                    decoration: const InputDecoration(
                      labelText: 'વેચાણ તારીખ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _addressController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'સરનામું (Address)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.home),
              ),
            ),
            const SizedBox(height: 14),

            // સેવ બટન
            ElevatedButton.icon(
              onPressed: _saveRecord,
              icon: const Icon(Icons.save),
              label: const Text('ગ્રાહકનો ડેટા સેવ કરો (Permanent Save)', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),

            // સેવ થયેલા રેકોર્ડ્સ બટન
            OutlinedButton.icon(
              onPressed: _showSavedListBottomSheet,
              icon: const Icon(Icons.list_alt),
              label: Text('સેવ કરેલા ગ્રાહકો જુઓ (${_savedRecords.length})'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),

            const SizedBox(height: 20),

            // બનાવનારની વિગત (Developer Contact Info)
            Card(
              elevation: 1,
              color: Colors.teal.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                child: Column(
                  children: [
                    const Text(
                      '🛠️ Application Developed By',
                      style: TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Dilipsinh Parmar',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.phone, size: 16, color: Colors.teal),
                        SizedBox(width: 6),
                        Text(
                          'Contact: +91 9574932281',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.teal),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ક્રેશ-ફ્રી સુરક્ષિત સ્કેનર સ્ક્રીન
class SafeScannerScreen extends StatefulWidget {
  final String title;
  final String hintText;
  const SafeScannerScreen({super.key, required this.title, required this.hintText});

  @override
  State<SafeScannerScreen> createState() => _SafeScannerScreenState();
}

class _SafeScannerScreenState extends State<SafeScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    returnImage: false,
  );
  bool _hasCaptured = false;
  final _manualController = TextEditingController();

  @override
  void dispose() {
    _scannerController.dispose();
    _manualController.dispose();
    super.dispose();
  }

  void _handleBarcode(BarcodeCapture capture) {
    if (_hasCaptured) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue != null && barcode!.rawValue!.isNotEmpty) {
      _hasCaptured = true;
      _scannerController.stop();
      Navigator.of(context).pop(barcode.rawValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.teal.shade800,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _scannerController.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _scannerController.switchCamera(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: _handleBarcode,
                  errorBuilder: (ctx, error) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          'કેમેરા ચાલુ થવામાં તકલીફ આવી.\nકૃપા કરીને નીચે મેન્યુઅલ નંબર દાખલ કરો.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    );
                  },
                ),
                Center(
                  child: Container(
                    width: 280,
                    height: 180,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.greenAccent, width: 2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      widget.hintText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12.0),
            color: Colors.grey.shade100,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualController,
                    decoration: const InputDecoration(
                      hintText: 'અથવા અહીં જાતે નંબર લખો',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    if (_manualController.text.trim().isNotEmpty) {
                      _scannerController.stop();
                      Navigator.of(context).pop(_manualController.text.trim());
                    }
                  },
                  child: const Text('OK'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

          ),
        ],
      ),
    );
  }
}
