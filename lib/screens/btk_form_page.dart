import 'package:flutter/material.dart';
import 'package:kolia/services/form_data_store.dart';
import 'package:kolia/services/database_helper.dart';
import 'package:kolia/screens/map_picker_page.dart';
import 'package:kolia/screens/plant_id_page.dart';
import 'package:kolia/widgets/drawing_canvas.dart';
import 'package:kolia/services/firebase_service.dart';
import 'package:kolia/services/auth_service.dart';
import 'dart:convert';
import 'dart:ui' as ui;
import 'dart:typed_data';

class BtkFormPage extends StatefulWidget {
  final int? draftId;
  final int? formId;
  final Map<String, dynamic>? cloudData;
  final bool readOnly;

  const BtkFormPage({
    super.key, 
    this.draftId, 
    this.formId, 
    this.cloudData,
    this.readOnly = false,
  });

  @override
  State<BtkFormPage> createState() => _BtkFormPageState();
}

class _BtkFormPageState extends State<BtkFormPage> {
  final _formKey = GlobalKey<FormState>();
  int _currentPage = 0;
  bool _isAdmin = false;
  
  // Page 2 & 3 Data
  List<Map<String, String>> _vegetationRows = [];
  List<Map<String, String>> _soilRows = [];
  
  // Page 4 Data (Geomass Table)
  List<Map<String, String>> _biomassRows = [];

  // Page 5 Data: Tree Taxation
  List<Map<String, String>> _treeTaxationRows = [];
  final _taxationPlotSizeController = TextEditingController();

  // Page 6 Data: Tree Phytomass Table
  List<Map<String, String>> _treePhytomassRows = [];
  
  // Page 7 Data
  String? _sketchBase64;
  final _sketchTitleController = TextEditingController();
  final _sketchIndexController = TextEditingController();
  final _sketchHeightController = TextEditingController();
  final _sketchAboveGroundController = TextEditingController();
  final _sketchBelowGroundController = TextEditingController();
  final _sketchFooterController = TextEditingController();
  
  // Page 1 Controllers
  final _btkIndexController = TextEditingController();
  final _landscapeNameController = TextEditingController();
  final _landscapeGenusNumberController = TextEditingController(text: '#');
  final _faciesNameController = TextEditingController();
  final _steksiController = TextEditingController(); 
  final _researcherController = TextEditingController();
  final _dateController = TextEditingController();
  final _locationController = TextEditingController(); // Just text
  final _coordsController = TextEditingController();   // With map picker
  final _physGeogCharController = TextEditingController();
  final _reliefTypeController = TextEditingController();
  final _morphologicalCharController = TextEditingController();
  final _modernGeomorphProcController = TextEditingController();
  final _migrationRegimeController = TextEditingController();
  final _moisteningDegreeController = TextEditingController();
  final _plantAssociationController = TextEditingController();
  final _soilTypeNameController = TextEditingController();
  final _soilSurfaceFormationController = TextEditingController();

  int? _currentDraftId;
  int? _currentFormId;
  String? _cloudId;
  String? _originalTeamName;
  String? _currentTeamId;
  bool _isLoading = false;
  bool _isInitializing = false;
  bool _isSuperscriptActive = false;

  final Map<String, String> _superscriptMap = {
    '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴', '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
    'a': 'ᵃ', 'b': 'ᵇ', 'c': 'ᶜ', 'd': 'ᵈ', 'e': 'ᵉ', 'f': 'ᶠ', 'g': 'ᵍ', 'h': 'ʰ', 'i': 'ⁱ', 'j': 'ʲ',
    'k': 'ᵏ', 'l': 'ˡ', 'm': 'ᵐ', 'n': 'ⁿ', 'o': 'ᵒ', 'p': 'ᵖ', 'r': 'ʳ', 's': 'ˢ', 't': 'ᵗ', 'u': 'ᵘ',
    'v': 'ᵛ', 'w': 'ʷ', 'x': 'ˣ', 'y': 'ʸ', 'z': 'ᶻ',
    'A': 'ᴬ', 'B': 'ᴮ', 'D': 'ᴰ', 'E': 'ᴱ', 'G': 'ᴳ', 'H': 'ᴴ', 'I': 'ᴵ', 'J': 'ᴶ', 'K': 'ᴷ', 'L': 'ᴸ',
    'M': 'ᴹ', 'N': 'ᴺ', 'O': 'ᴼ', 'P': 'ᴾ', 'R': 'ᴿ', 'T': 'ᵀ', 'U': 'ᵁ', 'V': 'ⱽ', 'W': 'ᵂ',
    '+': '⁺', '-': '⁻', '=': '⁼', '(': '⁽', ')': '⁾', '.': '˙', ',': '’',
  };

  @override
  void initState() {
    super.initState();
    _currentDraftId = widget.draftId;
    _currentFormId = widget.formId;
    
    _initData();
    
    // Ensure # is always present at the start of Landscape Genus Number
    _landscapeGenusNumberController.addListener(_ensureHashPrefix);

    // Setup auto-save listeners
    final controllers = [
      _btkIndexController,
      _landscapeNameController,
      _landscapeGenusNumberController,
      _faciesNameController,
      _steksiController,
      _researcherController,
      _dateController,
      _locationController,
      _coordsController,
      _physGeogCharController,
      _reliefTypeController,
      _morphologicalCharController,
      _modernGeomorphProcController,
      _migrationRegimeController,
      _moisteningDegreeController,
      _plantAssociationController,
      _soilTypeNameController,
      _soilSurfaceFormationController,
      _sketchTitleController,
      _sketchIndexController,
      _sketchHeightController,
      _sketchFooterController,
      _taxationPlotSizeController
    ];
    for (var controller in controllers) {
      controller.addListener(_autoSaveDraft);
    }
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);
    _isInitializing = true;
    
    final team = await AuthService.getLoggedInTeam();
    _isAdmin = team?.isAdmin ?? false;
    _currentTeamId = team?.id;
    // Set initial team name for new forms
    _originalTeamName ??= team?.name;
    
    if (widget.cloudData != null) {
      _fillFieldsFromData(widget.cloudData!);
    } else if (_currentFormId != null) {
      await _loadForm();
    } else {
      await _loadDraft();
    }
    
    _isInitializing = false;
    setState(() => _isLoading = false);
  }

  void _ensureHashPrefix() {
    String text = _landscapeGenusNumberController.text;
    if (!text.startsWith('#')) {
      _landscapeGenusNumberController.value = TextEditingValue(
        text: '#${text.replaceAll('#', '')}',
        selection: TextSelection.collapsed(offset: (text.replaceAll('#', '').length + 1)),
      );
    }
  }

  Future<void> _loadForm() async {
    if (_currentFormId != null) {
      final form = await DatabaseHelper.instance.getForm(_currentFormId!);
      if (form != null) {
        final data = form['data'] as Map<String, dynamic>;
        _fillFieldsFromData(data);
      }
    }
  }

  Future<void> _loadDraft() async {
    if (_currentDraftId != null) {
      final draft = await DatabaseHelper.instance.getDraft(_currentDraftId!);
      if (draft != null) {
        final data = draft['data'] as Map<String, dynamic>;
        _fillFieldsFromData(data);
      }
    }
  }

  void _fillFieldsFromData(Map<String, dynamic> data) {
    setState(() {
      _cloudId = data['id'];
      _originalTeamName = data['team_name'];
      _currentTeamId = data['team_id'];
      _btkIndexController.text = data['btk_index'] ?? '';
      _landscapeNameController.text = data['landscape_name'] ?? '';
      _landscapeGenusNumberController.text = data['landscape_genus_number'] ?? '#';
      _faciesNameController.text = data['facies_name'] ?? '';
      _steksiController.text = data['steksi'] ?? '';
      _researcherController.text = data['researcher'] ?? '';
      _dateController.text = data['date'] ?? '';
      _locationController.text = data['location'] ?? '';
      _coordsController.text = data['coords'] ?? '';
      _physGeogCharController.text = data['phys_geog_char'] ?? '';
      _reliefTypeController.text = data['relief_type'] ?? '';
      _morphologicalCharController.text = data['morphological_char'] ?? '';
      _modernGeomorphProcController.text = data['modern_geomorph_proc'] ?? '';
      _migrationRegimeController.text = data['migration_regime'] ?? '';
      _moisteningDegreeController.text = data['moistening_degree'] ?? '';
      _plantAssociationController.text = data['plant_association'] ?? '';
      _soilTypeNameController.text = data['soil_type_name'] ?? '';
      _soilSurfaceFormationController.text = data['soil_surface_formation'] ?? '';
      _taxationPlotSizeController.text = data['taxation_plot_size'] ?? '';
      _sketchBase64 = data['sketch_base64'];

      // Clean up old prefilled values from existing drafts
      String title = data['sketch_title'] ?? '';
      if (title == 'ბტკ-ის ვერტიკალური სტრუქტურა. ვერტ. სტრუქტ. ტიპის სახელწოდება:') title = '';
      _sketchTitleController.text = title;

      String index = data['sketch_index'] ?? '';
      if (index == 'ინდექსი:') index = '';
      _sketchIndexController.text = index;

      String height = data['sketch_height'] ?? '';
      if (height == 'სიმაღლე:') height = '';
      _sketchHeightController.text = height;

      _sketchAboveGroundController.text = data['sketch_above_ground'] ?? '';
      _sketchBelowGroundController.text = data['sketch_below_ground'] ?? '';

      String footer = data['sketch_footer'] ?? '';
      if (footer == 'ვერტიკალური პროფილის მიწისზედა ნაწილის დამოკიდებულება მიწისქვეშა ნაწილთან:') footer = '';
      _sketchFooterController.text = footer;

      // Load Tables
      if (data['vegetation_rows'] != null) {
        _vegetationRows = List<Map<String, String>>.from(
            (data['vegetation_rows'] as List).map((e) => Map<String, String>.from(e))
        );
      } else {
        _vegetationRows = [];
      }

      if (data['soil_rows'] != null) {
        _soilRows = List<Map<String, String>>.from(
            (data['soil_rows'] as List).map((e) => Map<String, String>.from(e))
        );
      } else {
        _soilRows = [];
      }

      if (data['biomass_rows'] != null) {
        _biomassRows = List<Map<String, String>>.from(
            (data['biomass_rows'] as List).map((e) => Map<String, String>.from(e))
        );
      } else {
        _biomassRows = List.generate(12, (_) => {
          'section': '',
          'p_percent': '', 'p_weight': '', 'p_qty': '',
          'l_percent': '', 'l_density': '', 'l_qty': '',
          'h_moist': '', 'h_qty': '',
          'f_percent': '', 'f_wet': '', 'f_dry': '',
          'r_qty': '',
        });
      }

      if (data['tree_taxation_rows'] != null) {
        _treeTaxationRows = List<Map<String, String>>.from(
            (data['tree_taxation_rows'] as List).map((e) => Map<String, String>.from(e))
        );
      } else {
        _treeTaxationRows = [];
      }

      if (data['tree_phytomass_rows'] != null) {
        _treePhytomassRows = List<Map<String, String>>.from(
            (data['tree_phytomass_rows'] as List).map((e) => Map<String, String>.from(e))
        );
      } else {
        _treePhytomassRows = List.generate(8, (_) => {
          'species': '',
          'v_vol': '', 'v_wet': '', 'v_dry': '',
          'w_wood': '', 'w_leaf': '', 'w_branch': '', 'w_root': '', 'w_total': '',
          'd_wood': '', 'd_leaf': '', 'd_branch': '', 'd_root': '', 'd_total': '',
        });
      }
    });
  }

  void _autoSaveDraft() async {
    if (_isInitializing || _isLoading || widget.readOnly) return;
    final draftId = await DatabaseHelper.instance.saveDraft(
      'ბტკ-ის ბლანკი',
      _btkIndexController.text.isEmpty ? 'ახალი ბლანკი' : 'ბტკ: ${_btkIndexController.text}',
      {
        'team_id': _currentTeamId,
        'team_name': _originalTeamName,
        'btk_index': _btkIndexController.text,
        'landscape_name': _landscapeNameController.text,
        'landscape_genus_number': _landscapeGenusNumberController.text,
        'facies_name': _faciesNameController.text,
        'steksi': _steksiController.text,
        'researcher': _researcherController.text,
        'date': _dateController.text,
        'location': _locationController.text,
        'coords': _coordsController.text,
        'phys_geog_char': _physGeogCharController.text,
        'relief_type': _reliefTypeController.text,
        'morphological_char': _morphologicalCharController.text,
        'modern_geomorph_proc': _modernGeomorphProcController.text,
        'migration_regime': _migrationRegimeController.text,
        'moistening_degree': _moisteningDegreeController.text,
        'plant_association': _plantAssociationController.text,
        'soil_type_name': _soilTypeNameController.text,
        'soil_surface_formation': _soilSurfaceFormationController.text,
        'taxation_plot_size': _taxationPlotSizeController.text,
        'vegetation_rows': _vegetationRows,
        'soil_rows': _soilRows,
        'biomass_rows': _biomassRows,
        'tree_taxation_rows': _treeTaxationRows,
        'tree_phytomass_rows': _treePhytomassRows,
        'sketch_base64': _sketchBase64,
        'sketch_title': _sketchTitleController.text,
        'sketch_index': _sketchIndexController.text,
        'sketch_height': _sketchHeightController.text,
        'sketch_footer': _sketchFooterController.text,
      },
      id: _currentDraftId,
    );
    _currentDraftId ??= draftId;
  }

  @override
  void dispose() {
    _landscapeGenusNumberController.removeListener(_ensureHashPrefix);
    _btkIndexController.dispose();
    _landscapeNameController.dispose();
    _landscapeGenusNumberController.dispose();
    _faciesNameController.dispose();
    _steksiController.dispose();
    _researcherController.dispose();
    _dateController.dispose();
    _locationController.dispose();
    _coordsController.dispose();
    _physGeogCharController.dispose();
    _reliefTypeController.dispose();
    _morphologicalCharController.dispose();
    _modernGeomorphProcController.dispose();
    _migrationRegimeController.dispose();
    _moisteningDegreeController.dispose();
    _plantAssociationController.dispose();
    _soilTypeNameController.dispose();
    _soilSurfaceFormationController.dispose();
    _taxationPlotSizeController.dispose();
    _sketchTitleController.dispose();
    _sketchIndexController.dispose();
    _sketchHeightController.dispose();
    _sketchFooterController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      setState(() {
        _dateController.text = picked.toString().split(' ')[0];
      });
      _autoSaveDraft();
    }
  }

  void _selectLocation() async {
    if (widget.readOnly) return;
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const MapPickerPage()),
    );
    if (result != null) {
      setState(() {
        _coordsController.text = result;
      });
      _autoSaveDraft();
    }
  }

  void _identifyPlant() async {
    if (widget.readOnly) return;
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const PlantIdPage()),
    );
    if (result != null) {
      setState(() {
        _plantAssociationController.text = result;
      });
      _autoSaveDraft();
    }
  }

  void _saveForm() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      
      final data = {
        'team_id': _currentTeamId,
        'team_name': _originalTeamName,
        'btk_index': _btkIndexController.text,
        'landscape_name': _landscapeNameController.text,
        'landscape_genus_number': _landscapeGenusNumberController.text,
        'facies_name': _faciesNameController.text,
        'steksi': _steksiController.text,
        'researcher': _researcherController.text,
        'date': _dateController.text,
        'location': _locationController.text,
        'coords': _coordsController.text,
        'phys_geog_char': _physGeogCharController.text,
        'relief_type': _reliefTypeController.text,
        'morphological_char': _morphologicalCharController.text,
        'modern_geomorph_proc': _modernGeomorphProcController.text,
        'migration_regime': _migrationRegimeController.text,
        'moistening_degree': _moisteningDegreeController.text,
        'plant_association': _plantAssociationController.text,
        'soil_type_name': _soilTypeNameController.text,
        'soil_surface_formation': _soilSurfaceFormationController.text,
        'taxation_plot_size': _taxationPlotSizeController.text,
        'vegetation_rows': _vegetationRows,
        'soil_rows': _soilRows,
        'biomass_rows': _biomassRows,
        'tree_taxation_rows': _treeTaxationRows,
        'tree_phytomass_rows': _treePhytomassRows,
        'sketch_base64': _sketchBase64,
        'sketch_title': _sketchTitleController.text,
        'sketch_index': _sketchIndexController.text,
        'sketch_height': _sketchHeightController.text,
        'sketch_above_ground': _sketchAboveGroundController.text,
        'sketch_below_ground': _sketchBelowGroundController.text,
        'sketch_footer': _sketchFooterController.text,
      };

      if (_cloudId != null) {
        data['id'] = _cloudId;
      }

      try {
        final localRecord = {
          'ტიპი': 'ბტკ-ის ბლანკი',
          'თარიღი': _dateController.text,
          'ბტკ ინდექსი': _btkIndexController.text,
          'ლანდშაფტი': _landscapeNameController.text,
          'მდებარეობა': _locationController.text,
          'კოორდინატები': _coordsController.text,
          'data': Map<String, dynamic>.from(data),
        };
        
        int dbId;
        // Check if we are editing an existing record (either from local or cloud)
        bool isEditingExisting = _currentFormId != null || widget.cloudData != null;

        if (isEditingExisting) {
          // Ask if they want to overwrite or create a copy
          final bool? createCopy = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('შენახვის მეთოდი'),
              content: const Text('გსურთ არსებული ბლანკის გადაწერა თუ ახალი ასლის შექმნა?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, true), // Create Copy
                  child: const Text('ასლის შექმნა'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, false), // Overwrite
                  child: const Text('გადაწერა'),
                ),
              ],
            ),
          );

          if (createCopy == null) {
            setState(() => _isLoading = false);
            return;
          }

          if (createCopy) {
            // Modify name to indicate it's a copy
            if (!_btkIndexController.text.contains('(ასლი)')) {
              _btkIndexController.text = '${_btkIndexController.text} (ასლი)';
            }
            localRecord['ბტკ ინდექსი'] = _btkIndexController.text;
            data['btk_index'] = _btkIndexController.text;
            // Remove cloud ID if it exists so it's treated as a new record in Firebase
            data.remove('id');
            _cloudId = null;
            localRecord['data'] = Map<String, dynamic>.from(data);

            dbId = await FormDataStore.addForm(localRecord);
            // After creating a copy, we treat it as a new form for the rest of the session
            _currentFormId = dbId; 
          } else {
            if (_currentFormId != null) {
              await DatabaseHelper.instance.updateForm(_currentFormId!, localRecord);
              dbId = _currentFormId!;
            } else {
              // It was a cloud form without a local ID yet
              dbId = await FormDataStore.addForm(localRecord);
              _currentFormId = dbId;
            }
          }
        } else {
          dbId = await FormDataStore.addForm(localRecord);
          _currentFormId = dbId;
        }

        // 2. Attempt to sync to Firebase
        bool syncSuccess = false;
        try {
          final cloudId = await FirebaseService.saveForm(data, localDbId: dbId);
          _cloudId = cloudId;
          syncSuccess = true;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('ბლანკი სინქრონიზებულია ღრუბელთან!'), backgroundColor: Colors.green),
            );
          }
        } catch (cloudError) {
          // If cloud fails, it's fine! It's already saved locally.
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('შენახულია ლოკალურად (ოფლაინ რეჟიმი)'), backgroundColor: Colors.orange),
            );
          }
        }

        // 3. Clear draft and exit
        if (_currentDraftId != null) {
          await DatabaseHelper.instance.deleteDraft(_currentDraftId!);
        }

        if (mounted) {
          setState(() => _isLoading = false);
          Navigator.pop(context, true); // Pass true to indicate successful save
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('შეცდომა შენახვისას: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.readOnly ? 'ბლანკის დათვალიერება' : 'ბტკ-ის ბლანკი'),
        actions: [
          if (!widget.readOnly)
            IconButton(onPressed: _saveForm, icon: const Icon(Icons.check_rounded))
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: _currentPage == 0 
                      ? _buildPageOne() 
                      : (_currentPage == 1 
                          ? _buildPageTwo() 
                          : (_currentPage == 2 
                              ? _buildPageThree() 
                              : (_currentPage == 3 
                                  ? _buildPageFour() 
                                  : (_currentPage == 4 
                                      ? _buildPageFive() 
                                      : (_currentPage == 5 ? _buildPageSix() : _buildPageSeven()))))),
                  ),
                ),
                _buildNavigationButtons(),
              ],
            ),
          ),
    );
  }

  Widget _buildPageOne() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('გვერდი 1: ზოგადი ინფორმაცია'),
        const SizedBox(height: 20),
        
        _buildField('ბტკ-ის ინდექსი:', _btkIndexController, readOnly: widget.readOnly),
        _buildField('ლანდშაფტის სახელწოდება:', _landscapeNameController, readOnly: widget.readOnly),
        _buildField('ლანდშაფტის გვარის ნომერი:', _landscapeGenusNumberController, readOnly: widget.readOnly, keyboardType: TextInputType.number),
        _buildField('ფაციესის სახელწოდება:', _faciesNameController, readOnly: widget.readOnly),
        _buildField('სტექსი:', _steksiController, readOnly: widget.readOnly),
        _buildField('მკვლევარი: (სახელი, გვარი ან ჯგუფის №)', _researcherController, readOnly: widget.readOnly),
        
        // Mandatory Date Picker
        _buildDatePickerField('თარიღი:', _dateController, readOnly: widget.readOnly),
        
        _buildField('ადგილმდებარეობა:', _locationController, readOnly: widget.readOnly),
        _buildLocationCoordsField('ადგილმდებარეობა (კორდინატებით):', _coordsController, readOnly: widget.readOnly),
        
        _buildField('ფიზიკურ-გეოგრაფიული დახასიათება. გეოლოგიური ფორმაცია:', _physGeogCharController, maxLines: 2, readOnly: widget.readOnly),
        _buildField('რელიეფის ტიპი:', _reliefTypeController, readOnly: widget.readOnly),
        _buildField('მორფოლოგიური დახასიათება:', _morphologicalCharController, maxLines: 2, readOnly: widget.readOnly),
        _buildField('თანამედროვე გეომორფოლოგიური პროცესები:', _modernGeomorphProcController, readOnly: widget.readOnly),
        _buildField('მიგრაციის რეჟიმი:', _migrationRegimeController, readOnly: widget.readOnly),
        _buildField('დატენიანების ხარისხი:', _moisteningDegreeController, readOnly: widget.readOnly),
        
        _buildPlantAssociationField(readOnly: widget.readOnly),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildPageTwo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('გვერდი 2: მცენარეული საფარი'),
        const SizedBox(height: 10),
        const Text('მცენარეულობის სახეობრივი შემადგენლობის დახასიათება:', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        
        ..._vegetationRows.asMap().entries.map((entry) {
          int idx = entry.key;
          var row = entry.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('სახეობა #${idx + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (!widget.readOnly)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => setState(() {
                        _vegetationRows.removeAt(idx);
                        _autoSaveDraft();
                      }),
                    )
                ],
              ),
              _buildInlineField('სახეობა:', row['species'] ?? '', (v) => row['species'] = v, readOnly: widget.readOnly),
              _buildInlineField('იარუსი:', row['layer'] ?? '', (v) => row['layer'] = v, readOnly: widget.readOnly),
              _buildInlineField('სიმაღლე:', row['height'] ?? '', (v) => row['height'] = v, readOnly: widget.readOnly, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              _buildInlineField('სიმძლავრე:', row['abundance'] ?? '', (v) => row['abundance'] = v, readOnly: widget.readOnly, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
              _buildInlineField('ფენოფაზა:', row['phenophase'] ?? '', (v) => row['phenophase'] = v, readOnly: widget.readOnly, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                ],
              ),
            ),
          );
        }),
        
        if (!widget.readOnly)
          Center(
            child: ElevatedButton.icon(
              onPressed: () => setState(() {
                _vegetationRows.add({'species': '', 'layer': '', 'height': '', 'abundance': '', 'phenophase': ''});
                _autoSaveDraft();
              }),
              icon: const Icon(Icons.add),
              label: const Text('სახეობის დამატება'),
            ),
          ),
      ],
    );
  }

  Widget _buildPageThree() {
    final bool isRestricted = !_isAdmin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('გვერდი 3: ნიადაგის აღწერა'),
        const SizedBox(height: 20),
        const Text('ნიადაგის პროფილის მორფოლოგიური დახასიათება:',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        
        ..._soilRows.asMap().entries.map((entry) {
          int idx = entry.key;
          var row = entry.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('ჰორიზონტი #${idx + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (!widget.readOnly)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => setState(() {
                        _soilRows.removeAt(idx);
                        _autoSaveDraft();
                      }),
                    )
                ],
              ),
              _buildInlineField(
                'გენეტიკური ჰორიზონტი:', 
                row['genetic_horizon'] ?? '', 
                (v) => row['genetic_horizon'] = v, 
                readOnly: widget.readOnly,
                showSuperscriptToggle: true,
              ),
              _buildInlineFieldWithInfo(
                'მორფოლოგიური დახასიათება:', 
                row['detailed_description'] ?? '', 
                (v) => row['detailed_description'] = v,
                'ფერი, მექანიკური შედგენილობა, სტრუქტურა, ფორიანობა, სიმკვრივე, ახალწარმონაქმნები, ხირხატიანობა %-ებში ჰორიზონტიდან, ფესვები %-ებში ნიადაგის მთელი პროფილიდან, ტენიანობა, ჰუმუსის ტიპი, ქვედა საზღვრის ხასიათი და სხვა.',
                readOnly: widget.readOnly
              ),
              _buildInlineField(
                'გეოჰორიზონტის ინდექსი:', 
                (!_isAdmin && (row['geohorizon_index']?.isEmpty ?? true)) ? 'ივსება კამერალურად' : (row['geohorizon_index'] ?? ''), 
                (v) => row['geohorizon_index'] = v, 
                readOnly: !_isAdmin || widget.readOnly,
                textColor: !_isAdmin && (row['geohorizon_index']?.isEmpty ?? true) ? Colors.red : null,
              ),
                ],
              ),
            ),
          );
        }),
        
        if (!widget.readOnly)
          Center(
            child: ElevatedButton.icon(
              onPressed: () => setState(() {
                _soilRows.add({'genetic_horizon': '', 'detailed_description': '', 'geohorizon_index': ''});
                _autoSaveDraft();
              }),
              icon: const Icon(Icons.add),
              label: const Text('ჰორიზონტის დამატება'),
            ),
          ),
        
        const SizedBox(height: 20),
        _buildField(
          'ნიადაგის ტიპის სახელწოდება:', 
          _soilTypeNameController, 
          readOnly: isRestricted || widget.readOnly,
          hintText: isRestricted ? 'ივსება კამერალურად' : null,
        ),
        _buildField(
          'ნიადაგის ზედაპირული ფორმაციის ტიპი:', 
          _soilSurfaceFormationController,
          readOnly: isRestricted || widget.readOnly,
          hintText: isRestricted ? 'ივსება კამერალურად' : null,
        ),
      ],
    );
  }

  Widget _buildInlineFieldWithInfo(String label, String initialValue, Function(String) onChanged, String info, {bool readOnly = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('ინფორმაცია'),
                      content: Text(info),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('დახურვა'))
                      ],
                    ),
                  );
                },
                child: const Icon(Icons.info_outline, size: 16, color: Colors.blue),
              ),
            ],
          ),
          TextFormField(
            initialValue: initialValue,
            readOnly: readOnly,
            onChanged: (v) {
              onChanged(v);
              _autoSaveDraft();
            },
            style: const TextStyle(fontSize: 14),
            maxLines: null,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: UnderlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineField(String label, String initialValue, Function(String) onChanged, {bool readOnly = false, TextInputType? keyboardType, Color? textColor, bool showSuperscriptToggle = false}) {
    final controller = TextEditingController(text: initialValue);
    // Set selection only if the current value matches initialValue to avoid jumping
    controller.selection = TextSelection.fromPosition(TextPosition(offset: initialValue.length));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
          Expanded(
            child: TextFormField(
              controller: controller,
              readOnly: readOnly,
              keyboardType: keyboardType,
              onChanged: (v) {
                String newVal = v;
                if (showSuperscriptToggle && _isSuperscriptActive && v.length > initialValue.length) {
                  // Get the last typed character based on cursor position
                  int cursorPosition = controller.selection.baseOffset;
                  if (cursorPosition > 0) {
                    String charTyped = v[cursorPosition - 1];
                    if (_superscriptMap.containsKey(charTyped)) {
                      String converted = _superscriptMap[charTyped]!;
                      newVal = v.replaceRange(cursorPosition - 1, cursorPosition, converted);
                      // Update controller directly to reflect conversion immediately
                      controller.value = controller.value.copyWith(
                        text: newVal,
                        selection: TextSelection.collapsed(offset: cursorPosition),
                      );
                    }
                  }
                }
                onChanged(newVal);
                _autoSaveDraft();
              },
              style: TextStyle(
                fontSize: 14, 
                color: textColor ?? (readOnly ? Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.6) : null),
                fontWeight: textColor != null ? FontWeight.bold : null,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: const UnderlineInputBorder(),
                suffixIcon: showSuperscriptToggle && !readOnly ? IconButton(
                  icon: Icon(
                    Icons.superscript, 
                    size: 18, 
                    color: _isSuperscriptActive ? Colors.blue : Colors.grey
                  ),
                  onPressed: () => setState(() => _isSuperscriptActive = !_isSuperscriptActive),
                  tooltip: 'Superscript Mode',
                ) : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationButtons() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          if (_currentPage > 0) ...[
            Expanded(
              child: ElevatedButton(
                onPressed: () => setState(() => _currentPage--),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                child: const FittedBox(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.arrow_back_ios_rounded, size: 16),
                      SizedBox(width: 4),
                      Text('წინა'),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          if (_currentPage < 6)
            Expanded(
              child: ElevatedButton(
                onPressed: () => setState(() => _currentPage++),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                child: const FittedBox(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('შემდეგი'),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios_rounded, size: 16),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ElevatedButton(
                onPressed: widget.readOnly ? () => Navigator.pop(context) : _saveForm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.readOnly ? Colors.grey : Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                child: FittedBox(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(widget.readOnly ? Icons.close_rounded : Icons.save_rounded, size: 18),
                      const SizedBox(width: 4),
                      Text(widget.readOnly ? 'დახურვა' : 'დასრულება'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, {int maxLines = 1, bool readOnly = false, String? hintText, TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            maxLines: maxLines,
            readOnly: readOnly,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              hintText: hintText,
              hintStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePickerField(String label, TextEditingController controller, {bool readOnly = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            readOnly: true,
            onTap: readOnly ? null : _selectDate,
            validator: (value) => value == null || value.isEmpty ? 'თარიღი სავალდებულოა' : null,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              suffixIcon: const Icon(Icons.calendar_today_rounded, size: 20),
              hintText: 'აირჩიეთ თარიღი',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationCoordsField(String label, TextEditingController controller, {bool readOnly = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            readOnly: readOnly,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              suffixIcon: readOnly ? null : IconButton(
                icon: const Icon(Icons.map_rounded),
                onPressed: _selectLocation,
                tooltip: 'რუკაზე არჩევა',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlantAssociationField({bool readOnly = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('მცენარეული ასოციაციის დასახელება:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _plantAssociationController,
            readOnly: readOnly,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              suffixIcon: readOnly ? null : IconButton(
                icon: const Icon(Icons.filter_center_focus_rounded),
                onPressed: _identifyPlant,
                tooltip: 'მცენარის იდენტიფიკაცია',
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openFullscreenSketch() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => FullscreenDrawingPage(
          initialBase64: _sketchBase64,
          readOnly: widget.readOnly,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _sketchBase64 = result;
      });
      _autoSaveDraft();
    }
  }

  Widget _buildPageFour() {
    final bool isRestricted = !_isAdmin;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('გვერდი 4: გეომასების კვლევა'),
        const SizedBox(height: 8),
        const Text(
          'ბტკ-ის ვერტიკალური პროფილის მიწისზედა ნაწილის გეომასები.',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),
        
        if (isRestricted)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: isDark ? Colors.amber.withValues(alpha: 0.1) : Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isDark ? Colors.amber.withValues(alpha: 0.3) : Colors.amber.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline, color: isDark ? Colors.amber.shade300 : Colors.amber.shade800, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'ეს ცხრილი ივსება კამერალურ პირობებში.',
                    style: TextStyle(
                      color: isDark ? Colors.amber.shade200 : const Color(0xFF856404), 
                      fontWeight: FontWeight.bold, 
                      fontSize: 13
                    ),
                  ),
                ),
              ],
            ),
          ),

        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade400),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Table(
              columnWidths: const {
                0: FixedColumnWidth(80),
                1: FixedColumnWidth(55),
                2: FixedColumnWidth(55),
                3: FixedColumnWidth(55),
                4: FixedColumnWidth(55),
                5: FixedColumnWidth(55),
                6: FixedColumnWidth(55),
                7: FixedColumnWidth(55),
                8: FixedColumnWidth(55),
                9: FixedColumnWidth(55),
                10: FixedColumnWidth(55),
                11: FixedColumnWidth(55),
                12: FixedColumnWidth(40),
              },
              border: TableBorder.all(color: isDark ? Colors.white10 : Colors.grey.shade400),
              children: [
                // Main Headers (Simulated merged visual)
                TableRow(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.blueGrey.shade800 : Colors.grey.shade100,
                  ),
                  children: [
                    _buildTableCell('სექციები', isHeader: true, textAlign: TextAlign.left),
                    _buildTableGroupCell('პედომასები', textAlign: TextAlign.left),
                    _buildTableGroupCell(''),
                    _buildTableGroupCell(''),
                    _buildTableGroupCell('ლითომასები', textAlign: TextAlign.left),
                    _buildTableGroupCell(''),
                    _buildTableGroupCell(''),
                    _buildTableGroupCell('ჰიდრომასები', textAlign: TextAlign.left),
                    _buildTableGroupCell(''),
                    _buildTableGroupCell('ფიტომასები', textAlign: TextAlign.left),
                    _buildTableGroupCell(''),
                    _buildTableGroupCell(''),
                    _buildTableCell('', isHeader: true),
                  ],
                ),
                // Sub Headers
                TableRow(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.blueGrey.shade800 : Colors.grey.shade100,
                  ),
                  children: [
                    _buildTableCell('', isHeader: true, textAlign: TextAlign.left), // Placeholder for first column
                    _buildTableCell('%', isHeader: true, textAlign: TextAlign.left),
                    _buildTableCell('მოც. წონა', isHeader: true, textAlign: TextAlign.left),
                    _buildTableCell('რაოდ.', isHeader: true, textAlign: TextAlign.left),
                    _buildTableCell('%', isHeader: true, textAlign: TextAlign.left),
                    _buildTableCell('სიმკვრ.', isHeader: true, textAlign: TextAlign.left),
                    _buildTableCell('რაოდ.', isHeader: true, textAlign: TextAlign.left),
                    _buildTableCell('სინოტ.', isHeader: true, textAlign: TextAlign.left),
                    _buildTableCell('რაოდ.', isHeader: true, textAlign: TextAlign.left),
                    _buildTableCell('%', isHeader: true, textAlign: TextAlign.left),
                    _buildTableCell('სველი', isHeader: true, textAlign: TextAlign.left),
                    _buildTableCell('მშრალი', isHeader: true, textAlign: TextAlign.left),
                    _buildTableCell('', isHeader: true),
                  ],
                ),
                // Data Rows
                ..._biomassRows.asMap().entries.map((entry) {
                  int idx = entry.key;
                  var row = entry.value;
                  return TableRow(
                    children: [
                      _buildTableInputCell(row['section'] ?? '', (v) => row['section'] = v, readOnly: isRestricted || widget.readOnly, width: 80, textAlign: TextAlign.left),
                      _buildTableInputCell(row['p_percent'] ?? '', (v) => row['p_percent'] = v, readOnly: isRestricted || widget.readOnly, textAlign: TextAlign.left),
                      _buildTableInputCell(row['p_weight'] ?? '', (v) => row['p_weight'] = v, readOnly: isRestricted || widget.readOnly, textAlign: TextAlign.left),
                      _buildTableInputCell(row['p_qty'] ?? '', (v) => row['p_qty'] = v, readOnly: isRestricted || widget.readOnly, textAlign: TextAlign.left),
                      _buildTableInputCell(row['l_percent'] ?? '', (v) => row['l_percent'] = v, readOnly: isRestricted || widget.readOnly, textAlign: TextAlign.left),
                      _buildTableInputCell(row['l_density'] ?? '', (v) => row['l_density'] = v, readOnly: isRestricted || widget.readOnly, textAlign: TextAlign.left),
                      _buildTableInputCell(row['l_qty'] ?? '', (v) => row['l_qty'] = v, readOnly: isRestricted || widget.readOnly, textAlign: TextAlign.left),
                      _buildTableInputCell(row['h_moist'] ?? '', (v) => row['h_moist'] = v, readOnly: isRestricted || widget.readOnly, textAlign: TextAlign.left),
                      _buildTableInputCell(row['h_qty'] ?? '', (v) => row['h_qty'] = v, readOnly: isRestricted || widget.readOnly, textAlign: TextAlign.left),
                      _buildTableInputCell(row['f_percent'] ?? '', (v) => row['f_percent'] = v, readOnly: isRestricted || widget.readOnly, textAlign: TextAlign.left),
                      _buildTableInputCell(row['f_wet'] ?? '', (v) => row['f_wet'] = v, readOnly: isRestricted || widget.readOnly, textAlign: TextAlign.left),
                      _buildTableInputCell(row['f_dry'] ?? '', (v) => row['f_dry'] = v, readOnly: isRestricted || widget.readOnly, textAlign: TextAlign.left),
                      // Delete button for supervisors
                      Container(
                        height: 30,
                        alignment: Alignment.center,
                        child: (isRestricted || widget.readOnly) 
                          ? const SizedBox.shrink()
                          : IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                setState(() {
                                  _biomassRows.removeAt(idx);
                                  _autoSaveDraft();
                                });
                              },
                            ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
        if (!(isRestricted || widget.readOnly))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _biomassRows.add({
                      'section': '', 'p_percent': '', 'p_weight': '', 'p_qty': '',
                      'l_percent': '', 'l_density': '', 'l_qty': '',
                      'h_moist': '', 'h_qty': '',
                      'f_percent': '', 'f_wet': '', 'f_dry': ''
                    });
                  });
                },
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('სექციის დამატება'),
                style: TextButton.styleFrom(
                  backgroundColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTableGroupCell(String title, {bool showBorder = false, TextAlign textAlign = TextAlign.center}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Alignment alignment = Alignment.center;
    if (textAlign == TextAlign.left) alignment = Alignment.centerLeft;
    if (textAlign == TextAlign.right) alignment = Alignment.centerRight;

    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.blueGrey.shade800 : Colors.grey.shade100,
        border: showBorder ? Border(right: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade400)) : null,
      ),
      child: Text(
        title,
        textAlign: textAlign,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 9,
        ),
      ),
    );
  }

  Widget _buildTableCell(String text, {bool isHeader = false, double? height, double? width, TextAlign textAlign = TextAlign.center}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Alignment alignment = Alignment.center;
    if (textAlign == TextAlign.left) alignment = Alignment.centerLeft;
    if (textAlign == TextAlign.right) alignment = Alignment.centerRight;

    return Container(
      height: height,
      width: width,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      color: isHeader 
          ? (isDark ? Colors.blueGrey.shade800 : Colors.grey.shade100) 
          : null,
      child: Text(
        text, 
        textAlign: textAlign,
        style: TextStyle(
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          fontSize: 10,
          color: isDark ? Colors.white70 : Colors.black87,
        ),
      ),
    );
  }

  Widget _buildTableInputCell(String initialValue, Function(String) onChanged, {bool readOnly = false, double? width, TextInputType? keyboardType, Color? textColor, double? fontSize, TextAlign textAlign = TextAlign.center}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      color: readOnly 
          ? (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade50) 
          : null,
      child: TextFormField(
        initialValue: initialValue,
        readOnly: readOnly,
        keyboardType: keyboardType,
        onChanged: (v) {
          onChanged(v);
          _autoSaveDraft();
        },
        style: TextStyle(
          fontSize: fontSize ?? 12,
          color: textColor ?? (readOnly ? theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5) : theme.textTheme.bodyMedium?.color),
          fontWeight: textColor != null ? FontWeight.bold : FontWeight.normal,
        ),
        textAlign: textAlign,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 8),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildPageFive() {
    final bool isRestricted = !_isAdmin;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('გვერდი 5: ხე-მცენარეულობის ტაქსაცია'),
        const SizedBox(height: 16),
        const Text(
          'ხე მცენარეების ფიტომასა',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 16),
        
        if (isRestricted)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: isDark ? Colors.amber.withValues(alpha: 0.1) : Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isDark ? Colors.amber.withValues(alpha: 0.3) : Colors.amber.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline, color: isDark ? Colors.amber.shade300 : Colors.amber.shade800, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'სვეტი "მოცულობა" ივსება კამერალურ პირობებში.',
                    style: TextStyle(
                      color: isDark ? Colors.amber.shade200 : const Color(0xFF856404), 
                      fontWeight: FontWeight.bold, 
                      fontSize: 13
                    ),
                  ),
                ),
              ],
            ),
          ),

        ..._treeTaxationRows.asMap().entries.map((entry) {
          int idx = entry.key;
          var row = entry.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('სახეობა #${idx + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (!widget.readOnly)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => setState(() {
                            _treeTaxationRows.removeAt(idx);
                            _autoSaveDraft();
                          }),
                        )
                    ],
                  ),
                  _buildInlineField('სახეობა:', row['species'] ?? '', (v) => row['species'] = v, readOnly: widget.readOnly),
                  _buildInlineField('D:', row['d'] ?? '', (v) => row['d'] = v, readOnly: widget.readOnly, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                  _buildInlineField('H:', row['h'] ?? '', (v) => row['h'] = v, readOnly: widget.readOnly, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                  _buildInlineField('K2:', row['k2'] ?? '', (v) => row['k2'] = v, readOnly: widget.readOnly, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                  _buildInlineField(
                    'მოცულობა:', 
                    isRestricted ? (row['volume']?.isNotEmpty == true ? row['volume']! : 'ივსება კამერალურად') : (row['volume'] ?? ''), 
                    (v) => row['volume'] = v, 
                    readOnly: isRestricted || widget.readOnly,
                    textColor: isRestricted && (row['volume']?.isEmpty ?? true) ? Colors.red : null,
                  ),
                ],
              ),
            ),
          );
        }),
        
        if (!widget.readOnly)
          Center(
            child: ElevatedButton.icon(
              onPressed: () => setState(() {
                _treeTaxationRows.add({'species': '', 'd': '', 'h': '', 'k2': '', 'volume': ''});
                _autoSaveDraft();
              }),
              icon: const Icon(Icons.add),
              label: const Text('სახეობის დამატება'),
            ),
          ),
        
        const SizedBox(height: 24),
        _buildField('ნაკვეთის ზომა:', _taxationPlotSizeController, hintText: 'მაგ: 50x100 m²', readOnly: widget.readOnly),
      ],
    );
  }


  Widget _buildPageSix() {
    final bool isRestricted = !_isAdmin;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('გვერდი 6: ხე მცენარეების ფიტომასა'),
        const SizedBox(height: 8),
        if (isRestricted)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: isDark ? Colors.amber.withValues(alpha: 0.1) : Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isDark ? Colors.amber.withValues(alpha: 0.3) : Colors.amber.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline, color: isDark ? Colors.amber.shade300 : Colors.amber.shade800, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'ეს ცხრილი ივსება კამერალურ პირობებში.',
                    style: TextStyle(
                      color: isDark ? Colors.amber.shade200 : const Color(0xFF856404), 
                      fontWeight: FontWeight.bold, 
                      fontSize: 13
                    ),
                  ),
                ),
              ],
            ),
          ),

        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: isDark ? Colors.white24 : Colors.grey.shade400),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Table(
              columnWidths: const {
                0: FixedColumnWidth(100), // სახეობა
                1: FixedColumnWidth(60),  // მმოც
                2: FixedColumnWidth(60),  // სველი
                3: FixedColumnWidth(60),  // მშრალი
                4: FixedColumnWidth(60),  // მერქნ
                5: FixedColumnWidth(60),  // ფოთლ
                6: FixedColumnWidth(60),  // ტოტ
                7: FixedColumnWidth(60),  // ფესვ
                8: FixedColumnWidth(60),  // ჯამი
                9: FixedColumnWidth(60),  // მერქნ
                10: FixedColumnWidth(60), // ფოთლ
                11: FixedColumnWidth(60), // ტოტ
                12: FixedColumnWidth(60), // ფესვ
                13: FixedColumnWidth(60), // ჯამი
                14: FixedColumnWidth(40), // delete
              },
              border: TableBorder.all(color: isDark ? Colors.white10 : Colors.grey.shade400),
              children: [
                TableRow(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.blueGrey.shade800 : Colors.grey.shade100,
                  ),
                  children: [
                    _buildTableCell('სახეობა', isHeader: true, textAlign: TextAlign.left),
                    _buildTableGroupCell('მმოც. წონა ტ/მ³', textAlign: TextAlign.left),
                    _buildTableGroupCell(''),
                    _buildTableGroupCell(''),
                    _buildTableGroupCell('სველი ფიტომასა', textAlign: TextAlign.left),
                    _buildTableGroupCell(''),
                    _buildTableGroupCell(''),
                    _buildTableGroupCell(''),
                    _buildTableGroupCell(''),
                    _buildTableGroupCell('მშრალი ფიტომასა', textAlign: TextAlign.left),
                    _buildTableGroupCell(''),
                    _buildTableGroupCell(''),
                    _buildTableGroupCell(''),
                    _buildTableGroupCell(''),
                    _buildTableCell('', isHeader: true),
                  ],
                ),
                TableRow(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.blueGrey.shade800 : Colors.grey.shade100,
                  ),
                  children: [
                    _buildTableCell('', isHeader: true),
                    _buildTableCell('მმოც.', isHeader: true, textAlign: TextAlign.left),
                    _buildTableCell('სველი', isHeader: true, textAlign: TextAlign.left),
                    _buildTableCell('მშრალი', isHeader: true, textAlign: TextAlign.left),
                    _buildTableCell('მერქნ.', isHeader: true, textAlign: TextAlign.left),
                    _buildTableCell('ფოთლ.', isHeader: true, textAlign: TextAlign.left),
                    _buildTableCell('ტოტ.', isHeader: true, textAlign: TextAlign.left),
                    _buildTableCell('ფესვ.', isHeader: true, textAlign: TextAlign.left),
                    _buildTableCell('ჯამი', isHeader: true, textAlign: TextAlign.left),
                    _buildTableCell('მერქნ.', isHeader: true, textAlign: TextAlign.left),
                    _buildTableCell('ფოთლ.', isHeader: true, textAlign: TextAlign.left),
                    _buildTableCell('ტოტ.', isHeader: true, textAlign: TextAlign.left),
                    _buildTableCell('ფესვ.', isHeader: true, textAlign: TextAlign.left),
                    _buildTableCell('ჯამი', isHeader: true, textAlign: TextAlign.left),
                    _buildTableCell('', isHeader: true),
                  ],
                ),
                ..._treePhytomassRows.asMap().entries.map((entry) {
                  int idx = entry.key;
                  var row = entry.value;
                  return TableRow(
                    children: [
                      _buildTableInputCell(
                        row['species'] ?? '', 
                        (v) => row['species'] = v, 
                        readOnly: isRestricted || widget.readOnly, 
                        width: 100,
                        textAlign: TextAlign.left,
                      ),
                      _buildTableInputCell(
                        row['v_vol'] ?? '', 
                        (v) => row['v_vol'] = v, 
                        readOnly: isRestricted || widget.readOnly,
                        textAlign: TextAlign.left,
                      ),
                      _buildTableInputCell(
                        row['v_wet'] ?? '', 
                        (v) => row['v_wet'] = v, 
                        readOnly: isRestricted || widget.readOnly,
                        textAlign: TextAlign.left,
                      ),
                      _buildTableInputCell(
                        row['v_dry'] ?? '', 
                        (v) => row['v_dry'] = v, 
                        readOnly: isRestricted || widget.readOnly,
                        textAlign: TextAlign.left,
                      ),
                      _buildTableInputCell(
                        row['w_wood'] ?? '', 
                        (v) => row['w_wood'] = v, 
                        readOnly: isRestricted || widget.readOnly,
                        textAlign: TextAlign.left,
                      ),
                      _buildTableInputCell(
                        row['w_leaf'] ?? '', 
                        (v) => row['w_leaf'] = v, 
                        readOnly: isRestricted || widget.readOnly,
                        textAlign: TextAlign.left,
                      ),
                      _buildTableInputCell(
                        row['w_branch'] ?? '', 
                        (v) => row['w_branch'] = v, 
                        readOnly: isRestricted || widget.readOnly,
                        textAlign: TextAlign.left,
                      ),
                      _buildTableInputCell(
                        row['w_root'] ?? '', 
                        (v) => row['w_root'] = v, 
                        readOnly: isRestricted || widget.readOnly,
                        textAlign: TextAlign.left,
                      ),
                      _buildTableInputCell(
                        row['w_total'] ?? '', 
                        (v) => row['w_total'] = v, 
                        readOnly: isRestricted || widget.readOnly,
                        textAlign: TextAlign.left,
                      ),
                      _buildTableInputCell(
                        row['d_wood'] ?? '', 
                        (v) => row['d_wood'] = v, 
                        readOnly: isRestricted || widget.readOnly,
                        textAlign: TextAlign.left,
                      ),
                      _buildTableInputCell(
                        row['d_leaf'] ?? '', 
                        (v) => row['d_leaf'] = v, 
                        readOnly: isRestricted || widget.readOnly,
                        textAlign: TextAlign.left,
                      ),
                      _buildTableInputCell(
                        row['d_branch'] ?? '', 
                        (v) => row['d_branch'] = v, 
                        readOnly: isRestricted || widget.readOnly,
                        textAlign: TextAlign.left,
                      ),
                      _buildTableInputCell(
                        row['d_root'] ?? '', 
                        (v) => row['d_root'] = v, 
                        readOnly: isRestricted || widget.readOnly,
                        textAlign: TextAlign.left,
                      ),
                      _buildTableInputCell(
                        row['d_total'] ?? '', 
                        (v) => row['d_total'] = v, 
                        readOnly: isRestricted || widget.readOnly,
                        textAlign: TextAlign.left,
                      ),
                      Container(
                        height: 30,
                        alignment: Alignment.center,
                        child: (isRestricted || widget.readOnly) 
                          ? const SizedBox.shrink()
                          : IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                setState(() {
                                  _treePhytomassRows.removeAt(idx);
                                  _autoSaveDraft();
                                });
                              },
                            ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
        if (!(isRestricted || widget.readOnly))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _treePhytomassRows.add({
                      'species': '',
                      'v_vol': '', 'v_wet': '', 'v_dry': '',
                      'w_wood': '', 'w_leaf': '', 'w_branch': '', 'w_root': '', 'w_total': '',
                      'd_wood': '', 'd_leaf': '', 'd_branch': '', 'd_root': '', 'd_total': '',
                    });
                    _autoSaveDraft();
                  });
                },
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('სახეობის დამატება'),
                style: TextButton.styleFrom(
                  backgroundColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
                ),
              ),
            ),
          ),
      ],
    );
  }
  Widget _buildPageSeven() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('გვერდი 7: ვერტიკალური სტრუქტურა'),
        const SizedBox(height: 16),
        _buildField(
          'დასახელება:', 
          _sketchTitleController, 
          readOnly: widget.readOnly,
          hintText: 'ბტკ-ის ვერტიკალური სტრუქტურა. ვერტ. სტრუქტ. ტიპის სახელწოდება:'
        ),
        _buildField(
          'ინდექსი:', 
          _sketchIndexController, 
          readOnly: widget.readOnly,
          hintText: 'ინდექსი:'
        ),
        _buildField(
          'სიმაღლე:', 
          _sketchHeightController, 
          readOnly: widget.readOnly,
          hintText: 'სიმაღლე:'
        ),
        
        const Text(
          'ბტკ-ის ვერტიკალური სტრუქტურის მიწისზედა ნაწილის ჩანახატი ვერტიკალური მასშტაბის დაცვით.',
          style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        
        GestureDetector(
          onTap: _openFullscreenSketch,
          child: Container(
            height: 300,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
              color: Colors.black12,
            ),
            child: _sketchBase64 != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      base64Decode(_sketchBase64!),
                      fit: BoxFit.contain,
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.edit_note, size: 48, color: Colors.grey),
                        const SizedBox(height: 8),
                        Text(widget.readOnly ? 'ჩანახატი არ არის' : 'დააჭირეთ ჩანახატის გასაკეთებლად (სრულ ეკრანზე)', 
                             textAlign: TextAlign.center,
                             style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
          ),
        ),
        
        const SizedBox(height: 16),
        const Text(
          'ვერტიკალური პროფილის მიწისზედა ნაწილის დამოკიდებულება მიწისქვედა ნაწილთან.',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _buildField(
          'სიმაღლე:', 
          _sketchHeightController, 
          readOnly: widget.readOnly,
          hintText: 'სიმაღლე:'
        ),
        _buildField(
          'მიწისზედა:', 
          _sketchAboveGroundController, 
          readOnly: widget.readOnly,
          hintText: 'მიწისზედა:'
        ),
        _buildField(
          'მიწისქვედა:', 
          _sketchBelowGroundController, 
          readOnly: widget.readOnly,
          hintText: 'მიწისქვედა:'
        ),
      ],
    );
  }
}

class FullscreenDrawingPage extends StatefulWidget {
  final String? initialBase64;
  final bool readOnly;
  const FullscreenDrawingPage({super.key, this.initialBase64, this.readOnly = false});

  @override
  State<FullscreenDrawingPage> createState() => _FullscreenDrawingPageState();
}

class _FullscreenDrawingPageState extends State<FullscreenDrawingPage> {
  String? _currentBase64;

  @override
  void initState() {
    super.initState();
    _currentBase64 = widget.initialBase64;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ჩანახატი'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (!widget.readOnly)
            TextButton(
              onPressed: () => Navigator.pop(context, _currentBase64),
              child: const Text('შენახვა', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: DrawingCanvas(
        readOnly: widget.readOnly,
        onDrawingChanged: (image) async {
          if (image != null) {
            final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
            if (byteData != null) {
              setState(() {
                _currentBase64 = base64Encode(byteData.buffer.asUint8List());
              });
            }
          } else {
            setState(() {
              _currentBase64 = null;
            });
          }
        },
      ),
    );
  }
}

