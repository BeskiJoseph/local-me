#!/usr/bin/env dart

import 'dart:io';
import 'dart:convert';

/// Detailed duplicate function and code analysis script
/// Focuses on finding exact duplicates and similar patterns

class DetailedAnalyzer {
  final String projectPath;
  final Map<String, List<FunctionInfo>> allFunctions = {};
  final List<String> duplicateFunctions = [];
  final List<String> suspiciousPatterns = [];
  
  DetailedAnalyzer(this.projectPath);

  Future<void> analyze() async {
    print('🔍 Starting detailed code analysis...\n');
    
    // 1. Find all Dart files
    final dartFiles = await _findDartFiles();
    print('📁 Found ${dartFiles.length} Dart files\n');
    
    // 2. Extract function signatures and bodies
    for (String file in dartFiles) {
      await _extractFunctions(file);
    }
    
    // 3. Find exact duplicates
    await _findExactDuplicates();
    
    // 4. Find similar patterns
    await _findSimilarPatterns();
    
    // 5. Check for unused functions
    await _findUnusedFunctions();
    
    // 6. Check for architectural issues
    await _checkArchitecturalIssues();
    
    print('\n✅ Detailed analysis complete!');
  }

  Future<List<String>> _findDartFiles() async {
    final List<String> files = [];
    
    await for (FileSystemEntity entity in Directory(projectPath).list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        if (!entity.path.contains('.g.dart') && 
            !entity.path.contains('.freezed.dart') &&
            !entity.path.contains('test/')) {
          files.add(entity.path);
        }
      }
    }
    
    return files;
  }

  Future<void> _extractFunctions(String filePath) async {
    try {
      final content = await File(filePath).readAsString();
      final lines = content.split('\n');
      
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        
        if (_isFunctionDefinition(line)) {
          final functionName = _extractFunctionName(line);
          if (functionName != null) {
            final functionBody = _extractFunctionBody(lines, i);
            final functionInfo = FunctionInfo(
              name: functionName,
              filePath: filePath,
              lineNumber: i + 1,
              body: functionBody,
              signature: line,
            );
            
            allFunctions.putIfAbsent(functionName, () => []).add(functionInfo);
          }
        }
      }
    } catch (e) {
      print('   ⚠️  Error analyzing $filePath: $e');
    }
  }

  bool _isFunctionDefinition(String line) {
    if (line.startsWith('//') || line.startsWith('/*') || line.isEmpty) {
      return false;
    }
    
    final patterns = [
      RegExp(r'^\s*\w+\s+\w+\s*\([^)]*\)\s*(async\s*)?{'),
      RegExp(r'^\s*Future\s*<\s*\w+\s*>\s+\w+\s*\([^)]*\)\s*(async\s*)?{'),
      RegExp(r'^\s*static\s+\w+\s+\w+\s*\([^)]*\)\s*(async\s*)?{'),
      RegExp(r'^\s*\w+\s*\([^)]*\)\s*(async\s*)?{'),
    ];
    
    return patterns.any((pattern) => pattern.hasMatch(line));
  }

  String? _extractFunctionName(String line) {
    final match = RegExp(r'(?:static\s+)?(?:\w+\s+)?(\w+)\s*\(').firstMatch(line);
    return match?.group(1);
  }

  String _extractFunctionBody(List<String> lines, int startIndex) {
    final buffer = StringBuffer();
    int braceCount = 0;
    bool foundStart = false;
    
    for (int i = startIndex; i < lines.length; i++) {
      final line = lines[i];
      
      if (!foundStart && line.contains('{')) {
        foundStart = true;
      }
      
      if (foundStart) {
        buffer.writeln(line);
        braceCount += '{'.allMatches(line).length;
        braceCount -= '}'.allMatches(line).length;
        
        if (braceCount == 0) {
          break;
        }
      }
    }
    
    return buffer.toString();
  }

  Future<void> _findExactDuplicates() async {
    print('🔍 Finding EXACT DUPLICATE FUNCTIONS...');
    
    bool foundDuplicates = false;
    
    for (final entry in allFunctions.entries) {
      if (entry.value.length > 1) {
        // Check for exact duplicate bodies
        final Map<String, List<FunctionInfo>> bodyMap = {};
        
        for (final func in entry.value) {
          final normalizedBody = _normalizeBody(func.body);
          bodyMap.putIfAbsent(normalizedBody, () => []).add(func);
        }
        
        for (final bodyEntry in bodyMap.entries) {
          if (bodyEntry.value.length > 1) {
            foundDuplicates = true;
            print('   🚨 EXACT DUPLICATE: ${entry.key}');
            for (final func in bodyEntry.value) {
              print('      - ${func.filePath.split('/').last}:${func.lineNumber}');
            }
            print('');
          }
        }
      }
    }
    
    if (!foundDuplicates) {
      print('   ✅ No exact duplicate functions found\n');
    }
  }

  String _normalizeBody(String body) {
    // Normalize whitespace and formatting for comparison
    return body
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\n\s*'), '\n')
        .trim();
  }

  Future<void> _findSimilarPatterns() async {
    print('🔍 Finding SIMILAR CODE PATTERNS...');
    
    // Common patterns to check
    final patterns = [
      'BackendService.toggleLike',
      'BackendService.toggleFollow',
      'ScaffoldMessenger.of(context).showSnackBar',
      'setState(()',
      'if (mounted)',
      'try {',
      'catch (e)',
      'Navigator.push',
      'await Future.delayed',
    ];
    
    for (final pattern in patterns) {
      await _checkPatternUsage(pattern);
    }
    
    print('   ✅ Pattern analysis complete\n');
  }

  Future<void> _checkPatternUsage(String pattern) async {
    final List<String> files = [];
    
    for (final entry in allFunctions.entries) {
      for (final func in entry.value) {
        if (func.body.contains(pattern)) {
          files.add('${func.filePath.split('/').last}:${func.lineNumber}');
        }
      }
    }
    
    if (files.length > 3) {
      print('   ⚠️  PATTERN REPEATED: "$pattern" found in ${files.length} functions');
      if (files.length <= 5) {
        for (final file in files) {
          print('      - $file');
        }
      } else {
        print('      - First 5: ${files.take(5).join(', ')}');
        print('      - ... and ${files.length - 5} more');
      }
      print('');
    }
  }

  Future<void> _findUnusedFunctions() async {
    print('🔍 Finding UNUSED FUNCTIONS...');
    
    // This is a simplified check - in reality, you'd need more sophisticated analysis
    for (final entry in allFunctions.entries) {
      final functionName = entry.key;
      
      // Skip common patterns that might be called indirectly
      if (functionName.startsWith('_') && 
          !functionName.contains('build') && 
          !functionName.contains('init') &&
          !functionName.contains('dispose')) {
        
        // Check if function is called anywhere
        bool isUsed = false;
        for (final file in await _findDartFiles()) {
          try {
            final content = await File(file).readAsString();
            if (content.contains(functionName) && 
                content.contains('()') &&
                !content.contains('//')) {
              isUsed = true;
              break;
            }
          } catch (e) {
            // Skip files that can't be read
          }
        }
        
        if (!isUsed && entry.value.length == 1) {
          print('   ⚠️  POSSIBLY UNUSED: $functionName in ${entry.value.first.filePath.split('/').last}');
        }
      }
    }
    
    print('   ✅ Unused function analysis complete\n');
  }

  Future<void> _checkArchitecturalIssues() async {
    print('🔍 Checking ARCHITECTURAL ISSUES...');
    
    // Check for specific issues
    await _checkDirectApiCalls();
    await _checkHardcodedValues();
    await _checkDuplicateErrorHandling();
    await _checkDuplicateLoadingStates();
    
    print('   ✅ Architectural analysis complete\n');
  }

  Future<void> _checkDirectApiCalls() async {
    print('   📡 Checking for direct API calls...');
    
    final dartFiles = await _findDartFiles();
    
    for (final file in dartFiles) {
      try {
        final content = await File(file).readAsString();
        
        // Look for direct HTTP calls
        if (content.contains('http.get') || 
            content.contains('http.post') ||
            content.contains('dio.')) {
          
          // Skip if it's in a service file
          if (!file.contains('/services/')) {
            print('      ⚠️  Direct API call in: ${file.split('/').last}');
          }
        }
      } catch (e) {
        // Skip
      }
    }
  }

  Future<void> _checkHardcodedValues() async {
    print('   🔒 Checking for hardcoded values...');
    
    final dartFiles = await _findDartFiles();
    
    for (final file in dartFiles) {
      try {
        final content = await File(file).readAsString();
        
        // Look for hardcoded URLs, keys, etc.
        if (content.contains('http://localhost') || 
            content.contains('http://192.168') ||
            content.contains('sk-') || // OpenAI API key pattern
            content.contains('AIza')) { // Google API key pattern
          print('      ⚠️  Hardcoded value in: ${file.split('/').last}');
        }
      } catch (e) {
        // Skip
      }
    }
  }

  Future<void> _checkDuplicateErrorHandling() async {
    print('   ❌ Checking for duplicate error handling...');
    
    final errorPatterns = [
      'ScaffoldMessenger.of(context).showSnackBar',
      'showSnackBar',
      'catch (e)',
      'Error:',
    ];
    
    for (final pattern in errorPatterns) {
      await _checkPatternUsage(pattern);
    }
  }

  Future<void> _checkDuplicateLoadingStates() async {
    print('   ⏳ Checking for duplicate loading states...');
    
    final loadingPatterns = [
      'CircularProgressIndicator',
      'isLoading',
      'setLoading',
      'loading = true',
    ];
    
    for (final pattern in loadingPatterns) {
      await _checkPatternUsage(pattern);
    }
  }
}

class FunctionInfo {
  final String name;
  final String filePath;
  final int lineNumber;
  final String body;
  final String signature;
  
  FunctionInfo({
    required this.name,
    required this.filePath,
    required this.lineNumber,
    required this.body,
    required this.signature,
  });
}

void main() async {
  final projectPath = Directory.current.path;
  
  print('🚀 Detailed Flutter App Analyzer');
  print('=' * 60);
  print('Project: $projectPath\n');
  
  final analyzer = DetailedAnalyzer(projectPath);
  await analyzer.analyze();
  
  print('=' * 60);
  print('📋 Detailed Analysis Summary:');
  print('   - Total functions analyzed: ${analyzer.allFunctions.values.fold(0, (sum, list) => sum + list.length)}');
  print('   - Files with functions: ${analyzer.allFunctions.keys.length}');
  
  print('\n🎯 Action Items:');
  print('   1. Refactor exact duplicate functions into shared utilities');
  print('   2. Create base classes for common patterns');
  print('   3. Remove unused private functions');
  print('   4. Centralize error handling patterns');
  print('   5. Use services for all API calls');
  
  print('\n📊 Code Quality Metrics:');
  print('   - Duplicate functions found: ${analyzer.duplicateFunctions.length}');
  print('   - Suspicious patterns: ${analyzer.suspiciousPatterns.length}');
}
