public with sharing class EC_Stedi_DataHandler {
    public static String insertRecords(EC_StediEligibility_Wrapper parsed_data) {
        System.debug('inside EC_Stedi_DataHandler.insertRecords');
        try {
            Map<String, CoverageBenefit> cbNamevsCbMap = new Map<String, CoverageBenefit>();
            Map<String, List<CoverageBenefitItem>> cbiMap = new Map<String, List<CoverageBenefitItem>>();
			List<CoverageBenefitItem> cbiToInsert = new List<CoverageBenefitItem>();
            
            //Member Plan
            if(parsed_data.memPlanId!=null){
                MemberPlan mp = new MemberPlan();
                mp.Id = parsed_data.memPlanId;
                mp.LastVerification = Date.Today();
                
                if(parsed_data.planStatus!=null && parsed_data.planStatus.size()>0){
                    for(EC_StediEligibility_Wrapper.cls_planStatus ps: parsed_data.planStatus){
                        if(ps.planDetails!=null){
                            mp.Insurance_Plan_Name__c = ps.planDetails;
                        }
                    }
                }
                
                if(parsed_data.planInformation!=null){
                    //mp.GroupNumber = (parsed_data.planInformation.groupNumber!=null ? parsed_data.planInformation.groupNumber : null);
                    //mp.Group__c = (parsed_data.planInformation.groupDescription!=null ? parsed_data.planInformation.groupDescription : null);
                    mp.Insurance_Plan_Name__c += (parsed_data.planInformation.planNumber!=null ? ' (' + parsed_data.planInformation.planNumber + ')' : '');
                }
                
                update mp;
            }
            system.debug('pr_accId--'+parsed_data.pr_accId);
            List<CoverageBenefit> existing_cbList = [SELECT Id, Name, code__c, Provider__c from CoverageBenefit WHERE MemberPlanId = :parsed_data.memPlanId AND Provider__c=:parsed_data.pr_accId];
            if(!existing_cbList.isEmpty()){
                for(CoverageBenefit cb : existing_cbList){
                    cbNamevsCbMap.put(cb.Name+cb.Provider__c, cb);
                    //system.debug(cb.Name+cb.Provider__c+'-->'+cb);
                }
            }
            
            List<CoverageBenefitItem> existing_cbItemList = [SELECT Id, Name, InPlanNetworkIndicator__c, timeQualifierCode__c, ServiceTypeCode, UniqueKey__c from CoverageBenefitItem WHERE CoverageBenefit.MemberPlanId = :parsed_data.memPlanId];
            Map<String, CoverageBenefitItem> existing_NameVsCBItemMap = new Map<String, CoverageBenefitItem>();
            if(!existing_cbItemList.isEmpty()){
                for(CoverageBenefitItem cbi : existing_cbItemList){
                    existing_NameVsCBItemMap.put(cbi.UniqueKey__c , cbi);
                }
            }
            
            for(EC_StediEligibility_Wrapper.cls_benefitsInformation bi: parsed_data.benefitsInformation) {
                //Coverage Benefit
                if (!cbNamevsCbMap.containsKey(bi.Name+parsed_data.pr_accId)) {
                    CoverageBenefit cb = new CoverageBenefit();
                    cb.MemberPlanId = parsed_data.memPlanId;	
                    cb.MemberId = parsed_data.accId;
                    cb.Name = bi.name;
                    cbNamevsCbMap.put(bi.Name+parsed_data.pr_accId, cb);
                }
				cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).code__c = bi.code;
                cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).VerificationDate = DateTime.Now();
                cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).Provider__c = parsed_data.pr_accId;

                if(bi.benefitsDateInformation!=null){
                    if(bi.benefitsDateInformation.planBegin!=null){
                        Date tmpDate = changeToDate(bi.benefitsDateInformation.planBegin);
                        if(tmpDate!=null){
                            cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitsDateInfo_PlanBegin__c = tmpDate;
                        }
                    }
                    if(bi.benefitsDateInformation.planEnd!=null){
                        Date tmpDate = changeToDate(bi.benefitsDateInformation.planEnd);
                        if(tmpDate!=null){
                            cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitsDateInfo_PlanEnd__c = tmpDate;
                        }
                    }
                }

                if(!cbiMap.containsKey(bi.Name+parsed_data.pr_accId))
                    cbiMap.put(bi.Name+parsed_data.pr_accId, new List<CoverageBenefitItem>());

                Integer counter = 0;
                //Coverage Benefit Items
                if(bi.serviceTypeCodes != null && bi.serviceTypeCodes.size()>0) {
                    for(String styc : bi.serviceTypeCodes){
                        CoverageBenefitItem cbi = new CoverageBenefitItem();

                        cbi.UniqueKey__c = styc;
                        if(bi.insuranceTypeCode!=null)
                            cbi.UniqueKey__c +='|' +  bi.insuranceTypeCode;
                        if(bi.timeQualifierCode!=null)
                            cbi.UniqueKey__c +='|' +  bi.timeQualifierCode;
                        if(bi.inPlanNetworkIndicatorCode!=null)
                            cbi.UniqueKey__c +='|' +  bi.inPlanNetworkIndicatorCode;
                        if(bi.eligibilityAdditionalInformation!=null)
                            cbi.UniqueKey__c += '|' + bi.eligibilityAdditionalInformation.industryCode;
                        if(bi.coverageLevel!=null)
                            cbi.UniqueKey__c +='|' +  bi.coverageLevel;
                        if(bi.code!=null)
                            cbi.UniqueKey__c +='|' +  bi.code;
                        if(bi.benefitPercent!=null)
                            cbi.UniqueKey__c +='|' +  bi.benefitPercent;
                        if(bi.trailerLoopIdentifierCode!=null)
                            cbi.UniqueKey__c +='|' +  bi.trailerLoopIdentifierCode;
                        if(bi.headerLoopIdentifierCode!=null)
                            cbi.UniqueKey__c +='|' +  bi.headerLoopIdentifierCode;
                        if(bi.benefitAmount!=null)
                            cbi.UniqueKey__c += '|' + bi.benefitAmount;
                        if(bi.benefitsDateInformation!=null && bi.benefitsDateInformation.plan!=null)
                            cbi.UniqueKey__c += '|' + bi.benefitsDateInformation.plan;
                        if(bi.additionalInformation!=null){
                            for(EC_StediEligibility_Wrapper.cls_additionalInformation ai : bi.additionalInformation){
                                if(ai.description!=null){
                                    cbi.UniqueKey__c +='|' + ai.description;
                                }
                            }
                        }
                        if(parsed_data.pr_accId!=null)
                            cbi.UniqueKey__c += '|' + parsed_data.pr_accId;
                        
                        //system.debug(cbi.UniqueKey__c);
                        
                        if(existing_NameVsCBItemMap.containsKey(cbi.UniqueKey__c)){
                            //system.debug(cbi.UniqueKey__c+'--->'+existing_NameVsCBItemMap.get(cbi.UniqueKey__c).Id);
                            cbi.Id = existing_NameVsCBItemMap.get(cbi.UniqueKey__c).Id;
                        }

                        cbi.MemberId = parsed_data.accId;
                        cbi.CoverageLevel = bi.coverageLevel;
                        cbi.ServiceTypeCode = styc;
                        cbi.InsuranceTypeCode__c = bi.insuranceTypeCode;
                        cbi.InsuranceType__c = bi.insuranceType;
                        cbi.PlanCoverage__c = bi.planCoverage;
                        cbi.TimeQualifier__c = bi.timeQualifier;
                        cbi.timeQualifierCode__c = bi.timeQualifierCode;
                        cbi.InPlanNetworkIndicator__c = bi.inPlanNetworkIndicator;
                        cbi.trailerLoopIdentifierCode__c = bi.trailerLoopIdentifierCode;
                        cbi.headerLoopIdentifierCode__c = bi.headerLoopIdentifierCode;
                        if(bi.benefitAmount!=null)
                            cbi.BenefitAmount__c = Decimal.valueOf(bi.benefitAmount);
                        cbi.QuantityQualifier__c = bi.quantityQualifier;
                        if(bi.benefitQuantity!=null)
                            cbi.BenefitQuantity__c = Decimal.valueOf(bi.benefitQuantity);
                        if(bi.benefitPercent!=null)
                            cbi.BenefitPercent__c = Decimal.valueOf(bi.benefitPercent);
                                       
                        //Eligibility Additional Information
                        if(bi.eligibilityAdditionalInformation!=null){
                            cbi.EligibilityAddInfo_CodeListQualifierCode__c = bi.eligibilityAdditionalInformation.codeListQualifierCode;
                            cbi.EligibilityAddInfo_IndustryCode__c = bi.eligibilityAdditionalInformation.industryCode;
                        }
                        
                        //Additional Information
                        if(bi.additionalInformation!=null){
                            String temp = '';
                            for(EC_StediEligibility_Wrapper.cls_additionalInformation ai : bi.additionalInformation){
                                if(ai.description!=null){
                                    temp += ai.description + '; ';
                                }
                            }
                            cbi.AdditionalInformation_Description__c = temp;
                        }
                        
                        //Benefits Additional Information
                        if(bi.benefitsAdditionalInformation!=null){
                            cbi.BenefitsAdditional_PlanNetworkIdNumber__c = bi.benefitsAdditionalInformation.planNetworkIdNumber;
                            cbi.BenefitsAdditional_HICNumber__c = bi.benefitsAdditionalInformation.hicNumber;
                        }
                        
                        //Benefits Date Info
                        if(bi.benefitsDateInformation!=null){
                            if(bi.benefitsDateInformation.periodStart!=null){
                                Date tmpDate = changeToDate(bi.benefitsDateInformation.periodStart);
                                if(tmpDate!=null){
                                    cbi.BenefitsDateInfo_PeriodStart__c = tmpDate;
                                }
                            }
                            if(bi.benefitsDateInformation.periodEnd!=null){
                                Date tmpDate = changeToDate(bi.benefitsDateInformation.periodEnd);
                                if(tmpDate!=null){
                                    cbi.BenefitsDateInfo_PeriodEnd__c = tmpDate;
                                }
                            }
                            if(bi.benefitsDateInformation.planBegin!=null){
                                Date tmpDate = changeToDate(bi.benefitsDateInformation.planBegin);
                                if(tmpDate!=null){
                                    cbi.BenefitsDateInfo_PlanBegin__c = tmpDate;
                                }
                            }
                            if(bi.benefitsDateInformation.planEnd!=null){
                                Date tmpDate = changeToDate(bi.benefitsDateInformation.planEnd);
                                if(tmpDate!=null){
                                    cbi.BenefitsDateInfo_PlanEnd__c = tmpDate;
                                }
                            }
                            if(bi.benefitsDateInformation.benefitBegin!=null){
                                Date tmpDate = changeToDate(bi.benefitsDateInformation.benefitBegin);
                                if(tmpDate!=null){
                                    cbi.BenefitsDateInfo_BenefitBegin__c = tmpDate;
                                }
                            }
                            if(bi.benefitsDateInformation.benefitEnd!=null){
                                Date tmpDate = changeToDate(bi.benefitsDateInformation.benefitEnd);
                                if(tmpDate!=null){
                                    cbi.BenefitsDateInfo_BenefitEnd__c = tmpDate;
                                }
                            }
                            if(bi.benefitsDateInformation.eligibilityBegin!=null){
                                Date tmpDate = changeToDate(bi.benefitsDateInformation.eligibilityBegin);
                                if(tmpDate!=null){
                                    cbi.BenefitsDateInfo_EligibilityBegin__c = tmpDate;
                                }
                            }
                            if(bi.benefitsDateInformation.eligibilityEnd!=null){
                                Date tmpDate = changeToDate(bi.benefitsDateInformation.eligibilityEnd);
                                if(tmpDate!=null){
                                    cbi.BenefitsDateInfo_EligibilityEnd__c = tmpDate;
                                }
                            }
                            if(bi.benefitsDateInformation.dateOfLastUpdate!=null){
                                Date tmpDate = changeToDate(bi.benefitsDateInformation.dateOfLastUpdate);
                                if(tmpDate!=null){
                                    cbi.BenefitsDateInfo_DateOfLastUpdate__c = tmpDate;
                                }
                            }
                        }
                        
                        //Benefits Related Entity
                        if(bi.benefitsRelatedEntity!=null){
                            cbi.BenefitsRelatedEntity_EntityIdentifier__c = bi.benefitsRelatedEntity.entityIdentifier;
                            cbi.BenefitsRelatedEntity_EntityType__c = bi.benefitsRelatedEntity.entityType;
                            if(bi.benefitsRelatedEntity.entityFirstname!=null){
                                cbi.BenefitsRelatedEntity_EntityName__c = bi.benefitsRelatedEntity.entityFirstname;
                                if(bi.benefitsRelatedEntity.entityName!=null)
                                    cbi.BenefitsRelatedEntity_EntityName__c += ' ' + bi.benefitsRelatedEntity.entityName;
                            }
                            else
                                cbi.BenefitsRelatedEntity_EntityName__c = bi.benefitsRelatedEntity.entityName;
                            cbi.BenefitsRelatedEntity_Identification__c = bi.benefitsRelatedEntity.entityIdentification;
                            cbi.BenefitsRelatedEntity_IdentificationVal__c = bi.benefitsRelatedEntity.entityIdentificationValue;
                            
                            if(bi.benefitsRelatedEntity.address!=null){
                                cbi.BenefitsRelatedEntity_Address1__c = bi.benefitsRelatedEntity.address.address1;
                                cbi.BenefitsRelatedEntity_City__c = bi.benefitsRelatedEntity.address.city;
                                cbi.BenefitsRelatedEntity_State__c = bi.benefitsRelatedEntity.address.state;
                                cbi.BenefitsRelatedEntity_PostalCode__c = bi.benefitsRelatedEntity.address.postalCode;
                            }
                            
                            if(bi.benefitsRelatedEntity.providerInformation!=null){
                                cbi.BenefitsRelatedEntity_ProviderCode__c = bi.benefitsRelatedEntity.providerInformation.providerCode;
                                cbi.BenefitsRelatedEntity_ReferenceId__c = bi.benefitsRelatedEntity.providerInformation.referenceIdentification;
                            }
                            
                            if(bi.benefitsRelatedEntity.contactInformation!=null){
                                if(bi.benefitsRelatedEntity.contactInformation.contacts!=null){
                                    String temp = '';
                                    for(EC_StediEligibility_Wrapper.cls_contacts con : bi.benefitsRelatedEntity.contactInformation.contacts){
                                        if(con.communicationMode!=null && con.communicationNumber!=null){
                                            String conNumber = con.communicationNumber.replaceAll('[^0-9]', '');
                                            if(conNumber.length() == 10){
                                                temp += con.communicationMode + ' : ' + conNumber.substring(0, 3) + '-' + conNumber.substring(3, 6) + '-' + conNumber.substring(6) + '; ';
                                            }
                                            else{
                                                temp += con.communicationMode + ' : ' + con.communicationNumber + '; '; 
                                            }
                                        }
                                    }
                                    cbi.BenefitsRelatedEntity_Com_Mode_Number__c = temp;
                                }
                            }
                        }
                        
                        cbi.Name = bi.serviceTypes[counter];
                        counter++;
                        
                        //system.debug(cbi);

                        cbiMap.get(bi.Name+parsed_data.pr_accId).add(cbi);
                    }
                }
                else{
                    //Additional Info
                    if(bi.additionalInformation!=null){
                        String temp = '';
                        for(EC_StediEligibility_Wrapper.cls_additionalInformation ai : bi.additionalInformation){
                            if(ai.description!=null){
                                temp += ai.description + '\n';
                            }
                        }
                        cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitNotes = temp;
                    }
                    
                    //Benefits Additional Information
                    if(bi.benefitsAdditionalInformation!=null){
                        cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitsAdditional_HICNumber__c = bi.benefitsAdditionalInformation.hicNumber;
                    }
                    
                    //Benefits Date Info
                    if(bi.benefitsDateInformation!=null){
                        if(bi.benefitsDateInformation.periodStart!=null){
                            Date tmpDate = changeToDate(bi.benefitsDateInformation.periodStart);
                            if(tmpDate!=null){
                                cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitPeriodStartDate = tmpDate;
                            }
                        }
                        if(bi.benefitsDateInformation.periodEnd!=null){
                            Date tmpDate = changeToDate(bi.benefitsDateInformation.periodEnd);
                            if(tmpDate!=null){
                                cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitPeriodEndDate = tmpDate;
                            }
                        }
                        if(bi.benefitsDateInformation.planBegin!=null){
                            Date tmpDate = changeToDate(bi.benefitsDateInformation.planBegin);
                            if(tmpDate!=null){
                                cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitsDateInfo_PlanBegin__c = tmpDate;
                            }
                        }
                        if(bi.benefitsDateInformation.planEnd!=null){
                            Date tmpDate = changeToDate(bi.benefitsDateInformation.planEnd);
                            if(tmpDate!=null){
                                cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitsDateInfo_PlanEnd__c = tmpDate;
                            }
                        }
                        if(bi.benefitsDateInformation.benefitBegin!=null){
                            Date tmpDate = changeToDate(bi.benefitsDateInformation.benefitBegin);
                            if(tmpDate!=null){
                                cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitsDateInfo_BenefitBegin__c = tmpDate;
                            }
                        }
                        if(bi.benefitsDateInformation.benefitEnd!=null){
                            Date tmpDate = changeToDate(bi.benefitsDateInformation.benefitEnd);
                            if(tmpDate!=null){
                                cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitsDateInfo_BenefitEnd__c = tmpDate;
                            }
                        }
                        if(bi.benefitsDateInformation.eligibilityBegin!=null){
                            Date tmpDate = changeToDate(bi.benefitsDateInformation.eligibilityBegin);
                            if(tmpDate!=null){
                                cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitsDateInfo_EligibilityBegin__c = tmpDate;
                            }
                        }
                        if(bi.benefitsDateInformation.eligibilityEnd!=null){
                            Date tmpDate = changeToDate(bi.benefitsDateInformation.eligibilityEnd);
                            if(tmpDate!=null){
                                cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitsDateInfo_EligibilityEnd__c = tmpDate;
                            }
                        }
                        if(bi.benefitsDateInformation.dateOfLastUpdate!=null){
                            Date tmpDate = changeToDate(bi.benefitsDateInformation.dateOfLastUpdate);
                            if(tmpDate!=null){
                                cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitsDateInfo_DateOfLastUpdate__c = tmpDate;
                            }
                        }
                    }
                    
                    //Benefits Related Entity
                    if(bi.benefitsRelatedEntity!=null){
                        cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitsRelatedEntity_EntityIdentifier__c = bi.benefitsRelatedEntity.entityIdentifier;
                        cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitsRelatedEntity_EntityType__c = bi.benefitsRelatedEntity.entityType;
                        if(bi.benefitsRelatedEntity.entityFirstname!=null){
                            cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitsRelatedEntity_EntityName__c = bi.benefitsRelatedEntity.entityFirstname;
                            if(bi.benefitsRelatedEntity.entityName!=null)
                                cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitsRelatedEntity_EntityName__c += ' ' + bi.benefitsRelatedEntity.entityName;
                        }
                        else
                            cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitsRelatedEntity_EntityName__c = bi.benefitsRelatedEntity.entityName;
                        //cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitsRelatedEntity_EntityName__c = bi.benefitsRelatedEntity.entityName;
                        cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitsRelatedEntity_Identification__c = bi.benefitsRelatedEntity.entityIdentification;
                        cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitsRelatedEntity_IdentificationVal__c = bi.benefitsRelatedEntity.entityIdentificationValue;
                        
                        if(bi.benefitsRelatedEntity.address!=null){
                            cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitsRelatedEntity_Address1__c = bi.benefitsRelatedEntity.address.address1;
                            cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitsRelatedEntity_City__c = bi.benefitsRelatedEntity.address.city;
                            cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitsRelatedEntity_State__c = bi.benefitsRelatedEntity.address.state;
                            cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitsRelatedEntity_PostalCode__c = bi.benefitsRelatedEntity.address.postalCode;
                        }
                        
                        if(bi.benefitsRelatedEntity.providerInformation!=null){
                            cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitsRelatedEntity_ProviderCode__c = bi.benefitsRelatedEntity.providerInformation.providerCode;
                            cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitsRelatedEntity_ReferenceId__c = bi.benefitsRelatedEntity.providerInformation.referenceIdentification;
                        }
                        
                        if(bi.benefitsRelatedEntity.contactInformation!=null){
                            if(bi.benefitsRelatedEntity.contactInformation.contacts!=null){
                                String temp = '';
                                for(EC_StediEligibility_Wrapper.cls_contacts con : bi.benefitsRelatedEntity.contactInformation.contacts){
                                    if(con.communicationMode!=null && con.communicationNumber!=null){
                                        String conNumber = con.communicationNumber.replaceAll('[^0-9]', '');
                                        if(conNumber.length() == 10){
                                            temp += con.communicationMode + ' : ' + conNumber.substring(0, 3) + '-' + conNumber.substring(3, 6) + '-' + conNumber.substring(6) + '; ';
                                        }
                                        else{
                                            temp += con.communicationMode + ' : ' + con.communicationNumber + '; '; 
                                        }
                                    }
                                }
                                cbNamevsCbMap.get(bi.Name+parsed_data.pr_accId).BenefitsRelatedEntity_Com_Mode_Number__c = temp;
                            }
                        }
                    }
                }
            }
            
            upsert cbNamevsCbMap.values();
            
            if(cbiMap.values().size() > 0) {
                for(String cbName: cbiMap.keySet()) {
                    if(cbiMap.containskey(cbName)){
                        for(CoverageBenefitItem cbitem : cbiMap.get(cbName)){
                            if(cbitem.Id==null)
                                cbitem.CoverageBenefitId = cbNamevsCbMap.get(cbName).Id;
                            
                            cbiToInsert.add(cbitem);
                            system.debug(cbitem.Id);
                            system.debug(cbitem.Name);
                            system.debug(cbitem.BenefitPercent__c);

                        }
                    }
                }
               // system.debug(cbiToInsert.size());
                upsert cbiToInsert;  
            }
            
            return 'Success';
        
        } catch (Exception e) {
            System.debug('EC_Stedi_DataHandler' + e.getLineNumber());
            System.debug('EC_Stedi_DataHandler' + e.getMessage());
            System.debug('EC_Stedi_DataHandler' + e.getCause());
            // Triton.instance.addError(TritonTypes.Area.Stedi, e);
            return e.getMessage();
        }
    }
    
    public static Date changeToDate(String dateStr){
        if(dateStr.length() == 8){
            dateStr.replaceAll('[^0-9]', '');
            
            // Extract year, month, and day
            Integer year = Integer.valueOf(dateStr.substring(0, 4));
            Integer month = Integer.valueOf(dateStr.substring(4, 6));
            Integer day = Integer.valueOf(dateStr.substring(6, 8));
            
            // Convert to Date format
            Date formattedDate = Date.newInstance(year, month, day);
            
            return formattedDate;
        }
        else
            return null;
    }
}