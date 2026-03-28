#!/usr/bin/env dart

import 'dart:io';
import 'dart:convert';

/// Comprehensive app analysis script
/// Tests for duplicate functions, unused code, and architectural issues

class AppAnalyzer {
  final String projectPath;
  final Map<String, List<String>> functionDefinitions = {};
  final Map<String, List<String>> classDefinitions = {};
  final Map<String, List<String>> importStatements = {};
  final List<String> allFiles = [];
  
  AppAnalyzer(this.projectPath);

  Future<void> analyze() async {
    print('🔍 Starting comprehensive app analysis...\n');
    
    // 1. Find all Dart files
    await _findDartFiles();
    
    // 2. Analyze each file
    for (String file in allFiles) {
      await _analyzeFile(file);
    }
    
    // 3. Run analysis tests
    await _runDuplicateFunctionTest();
    await _runUnusedImportTest();
    await _runDuplicateClassTest();
    await _runCodeComplexityTest();
    await _runArchitecturalTest();
    
    print('\n✅ Analysis complete!');
  }

  Future<void> _findDartFiles() async {
    print('📁 Scanning for Dart files...');
    
    await for (FileSystemEntity entity in Directory(projectPath).list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        // Skip generated files and test files
        if (!entity.path.contains('.g.dart') && 
            !entity.path.contains('.freezed.dart') &&
            !entity.path.contains('test/')) {
          allFiles.add(entity.path);
        }
      }
    }
    
    print('   Found ${allFiles.length} Dart files\n');
  }

  Future<void> _analyzeFile(String filePath) async {
    try {
      final content = await File(filePath).readAsString();
      final lines = content.split('\n');
      
      List<String> functions = [];
      List<String> classes = [];
      List<String> imports = [];
      
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        
        // Extract function definitions
        if (_isFunctionDefinition(line)) {
          final functionName = _extractFunctionName(line);
          if (functionName != null) {
            functions.add('$functionName (${filePath.split('/').last}:${i + 1})');
          }
        }
        
        // Extract class definitions
        if (_isClassDefinition(line)) {
          final className = _extractClassName(line);
          if (className != null) {
            classes.add('$className (${filePath.split('/').last}:${i + 1})');
          }
        }
        
        // Extract import statements
        if (line.startsWith('import ')) {
          imports.add(line);
        }
      }
      
      if (functions.isNotEmpty) {
        functionDefinitions[filePath] = functions;
      }
      if (classes.isNotEmpty) {
        classDefinitions[filePath] = classes;
      }
      if (imports.isNotEmpty) {
        importStatements[filePath] = imports;
      }
      
    } catch (e) {
      print('   ⚠️  Error analyzing $filePath: $e');
    }
  }

  bool _isFunctionDefinition(String line) {
    // Skip comments and empty lines
    if (line.startsWith('//') || line.startsWith('/*') || line.isEmpty) {
      return false;
    }
    
    // Match function patterns
    final patterns = [
      RegExp(r'^\s*\w+\s+\w+\s*\([^)]*\)\s*(async\s*)?{'), // Named function
      RegExp(r'^\s*\w+\s+\w+\s*\([^)]*\)\s*(async\s*)?=>'), // Arrow function
      RegExp(r'^\s*Future\s*<\s*\w+\s*>\s+\w+\s*\([^)]*\)\s*(async\s*)?{'), // Future function
      RegExp(r'^\s*static\s+\w+\s+\w+\s*\([^)]*\)\s*(async\s*)?{'), // Static function
      RegExp(r'^\s*\w+\s*\([^)]*\)\s*(async\s*)?{'), // Constructor-like function
    ];
    
    return patterns.any((pattern) => pattern.hasMatch(line));
  }

  String? _extractFunctionName(String line) {
    // Extract function name using regex
    final match = RegExp(r'(?:static\s+)?(?:\w+\s+)?(\w+)\s*\(').firstMatch(line);
    return match?.group(1);
  }

  bool _isClassDefinition(String line) {
    return RegExp(r'^\s*(abstract\s+)?class\s+\w+').hasMatch(line);
  }

  String? _extractClassName(String line) {
    final match = RegExp(r'class\s+(\w+)').firstMatch(line);
    return match?.group(1);
  }

  Future<void> _runDuplicateFunctionTest() async {
    print('🔍 Testing for DUPLICATE FUNCTIONS...');
    
    final Map<String, List<String>> functionMap = {};
    
    // Build function map
    for (final entry in functionDefinitions.entries) {
      for (final function in entry.value) {
        final name = function.split(' ')[0];
        functionMap.putIfAbsent(name, () => []).add(function);
      }
    }
    
    // Find duplicates
    bool foundDuplicates = false;
    for (final entry in functionMap.entries) {
      if (entry.value.length > 1) {
        foundDuplicates = true;
        print('   🚨 DUPLICATE FUNCTION: ${entry.key}');
        for (final location in entry.value) {
          print('      - $location');
        }
        print('');
      }
    }
    
    if (!foundDuplicates) {
      print('   ✅ No duplicate functions found\n');
    }
  }

  Future<void> _runUnusedImportTest() async {
    print('🔍 Testing for UNUSED IMPORTS...');
    
    for (final entry in importStatements.entries) {
      final filePath = entry.key;
      final imports = entry.value;
      
      try {
        final content = await File(filePath).readAsString();
        
        for (final import in imports) {
          final importName = _extractImportName(import);
          if (importName != null && !_isImportUsed(content, importName, import)) {
            print('   ⚠️  UNUSED IMPORT in ${filePath.split('/').last}: $import');
          }
        }
      } catch (e) {
        print('   ⚠️  Error checking imports in $filePath: $e');
      }
    }
    
    print('   ✅ Import analysis complete\n');
  }

  String? _extractImportName(String import) {
    // Extract the main part from import statement
    if (import.contains("package:")) {
      return import.split("package:")[1].split("/").last;
    } else if (import.contains("import '")) {
      return import.split("import '")[1].split("'").first.split("/").last;
    }
    return null;
  }

  bool _isImportUsed(String content, String importName, String fullImport) {
    // Check if import is actually used in the content
    if (fullImport.contains('show ')) {
      // Only check shown items
      final shownItems = fullImport.split('show ')[1].split('}')[0];
      return shownItems.split(',').any((item) => 
        content.contains(item.trim()) && !content.contains('//'));
    }
    
    // Check if import name is used
    final cleanName = importName.replaceAll('.dart', '');
    return content.contains(cleanName) && !content.contains('//');
  }

  Future<void> _runDuplicateClassTest() async {
    print('🔍 Testing for DUPLICATE CLASSES...');
    
    final Map<String, List<String>> classMap = {};
    
    // Build class map
    for (final entry in classDefinitions.entries) {
      for (final classDef in entry.value) {
        final name = classDef.split(' ')[0];
        classMap.putIfAbsent(name, () => []).add(classDef);
      }
    }
    
    // Find duplicates
    bool foundDuplicates = false;
    for (final entry in classMap.entries) {
      if (entry.value.length > 1) {
        foundDuplicates = true;
        print('   🚨 DUPLICATE CLASS: ${entry.key}');
        for (final location in entry.value) {
          print('      - $location');
        }
        print('');
      }
    }
    
    if (!foundDuplicates) {
      print('   ✅ No duplicate classes found\n');
    }
  }

  Future<void> _runCodeComplexityTest() async {
    print('🔍 Testing for CODE COMPLEXITY ISSUES...');
    
    for (final filePath in allFiles) {
      try {
        final content = await File(filePath).readAsString();
        final lines = content.split('\n');
        
        int lineCount = lines.length;
        int functionCount = functionDefinitions[filePath]?.length ?? 0;
        int classCount = classDefinitions[filePath]?.length ?? 0;
        
        // Flag potential issues
        if (lineCount > 500) {
          print('   ⚠️  LARGE FILE: ${filePath.split('/').last} ($lineCount lines)');
        }
        
        if (functionCount > 20) {
          print('   ⚠️  MANY FUNCTIONS: ${filePath.split('/').last} ($functionCount functions)');
        }
        
        // Check for deeply nested code
        int maxNesting = 0;
        int currentNesting = 0;
        
        for (final line in lines) {
          final openBraces = '{'.allMatches(line).length;
          final closeBraces = '}'.allMatches(line).length;
          currentNesting += openBraces - closeBraces;
          maxNesting = maxNesting > currentNesting ? maxNesting : currentNesting;
        }
        
        if (maxNesting > 5) {
          print('   ⚠️  DEEP NESTING: ${filePath.split('/').last} (max depth: $maxNesting)');
        }
        
      } catch (e) {
        print('   ⚠️  Error analyzing complexity for $filePath: $e');
      }
    }
    
    print('   ✅ Complexity analysis complete\n');
  }

  Future<void> _runArchitecturalTest() async {
    print('🔍 Testing for ARCHITECTURAL ISSUES...');
    
    // Check for service layer consistency
    final serviceFiles = allFiles.where((f) => f.contains('/services/')).toList();
    print('   📊 Service layer files: ${serviceFiles.length}');
    
    // Check for mixin usage
    final mixinFiles = allFiles.where((f) => f.contains('/mixins/')).toList();
    print('   📊 Mixin files: ${mixinFiles.length}');
    
    // Check for utility files
    final utilFiles = allFiles.where((f) => f.contains('/utils/')).toList();
    print('   📊 Utility files: ${utilFiles.length}');
    
    // Check for proper separation of concerns
    int widgetFiles = allFiles.where((f) => 
      f.contains('/widgets/') || f.contains('/screens/')).length;
    print('   📊 UI files (widgets/screens): $widgetFiles');
    
    // Check for potential architectural violations
    for (final filePath in allFiles) {
      try {
        final content = await File(filePath).readAsString();
        
        // Check for direct API calls in UI components
        if ((filePath.contains('/widgets/') || filePath.contains('/screens/')) &&
            content.contains('http.') && !content.contains('BackendService')) {
          print('   ⚠️  DIRECT API CALL in UI: ${filePath.split('/').last}');
        }
        
        // Check for hardcoded URLs
        if (content.contains('http://localhost') || content.contains('http://192.168')) {
          print('   ⚠️  HARDCODED URL: ${filePath.split('/').last}');
        }
        
      } catch (e) {
        print('   ⚠️  Error in architectural test for $filePath: $e');
      }
    }
    
    print('   ✅ Architectural analysis complete\n');
  }
}

void main() async {
  final projectPath = Directory.current.path;
  
  print('🚀 Flutter App Analyzer');
  print('=' * 50);
  print('Project: $projectPath\n');
  
  final analyzer = AppAnalyzer(projectPath);
  await analyzer.analyze();
  
  print('=' * 50);
  print('📋 Analysis Summary:');
  print('   - Checked ${analyzer.allFiles.length} Dart files');
  print('   - Found ${analyzer.functionDefinitions.values.fold(0, (sum, list) => sum + list.length)} total functions');
  print('   - Found ${analyzer.classDefinitions.values.fold(0, (sum, list) => sum + list.length)} total classes');
  print('\n🎯 Recommendations:');
  print('   1. Fix any duplicate functions/classes found');
  print('   2. Remove unused imports to reduce bundle size');
  print('   3. Consider breaking down large files');
  print('   4. Reduce nesting depth for better readability');
  print('   5. Use BackendService for all API calls');
}
